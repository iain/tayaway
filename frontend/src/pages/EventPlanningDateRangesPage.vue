<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import { PlusIcon, TrashIcon } from '@heroicons/vue/24/outline'
import { useAuthStore, useDatePollsStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import type { HydratedDateRange } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import DateRangeModal from '@/components/events/DateRangeModal.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import VotersList from '@/components/votes/VotersList.vue'
import PrimaryButton from '@/components/common/PrimaryButton.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'

const route = useRoute()
const authStore = useAuthStore()
const datePollsStore = useDatePollsStore()
const { currentMemberId } = storeToRefs(authStore)
const { addDays } = useCalendar()

const eventId = computed(() => route.params.id as string)

const { event } = useHydratedEvent(eventId)

const showDateRangeModal = ref(false)
const modalPreselectedStart = ref<string | null>(null)
const modalPreselectedEnd = ref<string | null>(null)

const confirmingDateRange = ref<HydratedDateRange | null>(null)

const isOwner = computed(() => {
  return currentMemberId.value === event.value?.memberId
})

const dateRanges = computed(() => {
  return event.value?.datePoll?.dateRanges ?? []
})

function handleAddDateRange(): void {
  if (dateRanges.value.length > 0) {
    const sortedRanges = [...dateRanges.value].sort((a, b) =>
      a.endDate.localeCompare(b.endDate)
    )
    const lastRange = sortedRanges[sortedRanges.length - 1]!
    modalPreselectedStart.value = addDays(lastRange.startDate, 7)
    modalPreselectedEnd.value = addDays(lastRange.endDate, 7)
  } else {
    modalPreselectedStart.value = null
    modalPreselectedEnd.value = null
  }
  showDateRangeModal.value = true
}

async function handleDateRangeModalSave(
  startDate: string,
  endDate: string
): Promise<void> {
  if (!event.value) return

  try {
    await datePollsStore.addDateRange(event.value.id, startDate, endDate)
    showDateRangeModal.value = false
  } catch {
    // Error handled by store
  }
}

function handleDeleteClick(dateRange: HydratedDateRange): void {
  if (dateRange.votes.length > 0) {
    confirmingDateRange.value = dateRange
  } else {
    deleteRange(dateRange.id)
  }
}

async function deleteRange(dateRangeId: string): Promise<void> {
  if (!event.value) return
  try {
    await datePollsStore.removeDateRange(event.value.id, dateRangeId)
    confirmingDateRange.value = null
  } catch {
    // Error handled by store
  }
}
</script>

<template>
  <div>
    <div v-if="!event" class="text-gray-500 dark:text-stone-400">
      Event not found
    </div>

    <div v-else-if="!event.datePoll" class="text-gray-500 dark:text-stone-400">
      No date poll found for this event.
    </div>

    <div v-else>
      <header class="mb-8">
        <h1
          class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
        >
          Edit Date Ranges
        </h1>
      </header>

      <section>
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            Date Options
          </h2>
          <PrimaryButton
            v-if="isOwner"
            :disabled="datePollsStore.loading"
            @click="handleAddDateRange"
          >
            <PlusIcon class="size-4" />
            Add Date Range
          </PrimaryButton>
        </div>

        <div v-if="dateRanges.length === 0" class="py-8 text-center">
          <p class="mb-4 text-gray-500 dark:text-stone-400">
            No date ranges added yet.
          </p>
          <PrimaryButton
            v-if="isOwner"
            :disabled="datePollsStore.loading"
            @click="handleAddDateRange"
          >
            <PlusIcon class="size-4" />
            Add Date Range
          </PrimaryButton>
        </div>

        <ul v-else class="space-y-2">
          <li
            v-for="dateRange in dateRanges"
            :key="dateRange.id"
            data-testid="date-range-item"
            class="flex items-center justify-between rounded-lg bg-white px-4 py-3 shadow dark:bg-stone-800"
          >
            <div>
              <span class="text-sm font-medium text-gray-900 dark:text-white">
                <DateRangeDisplay
                  :start-date="dateRange.startDate"
                  :end-date="dateRange.endDate"
                />
              </span>
              <span class="ml-3 text-sm text-gray-500 dark:text-stone-400">
                {{ dateRange.voteSummary.total }}
                {{ dateRange.voteSummary.total === 1 ? 'vote' : 'votes' }}
              </span>
            </div>
            <button
              v-if="isOwner"
              type="button"
              :disabled="datePollsStore.loading"
              class="ml-4 text-gray-400 hover:text-red-500 disabled:opacity-50 dark:text-stone-500 dark:hover:text-red-400"
              @click="handleDeleteClick(dateRange)"
            >
              <TrashIcon class="size-4" />
              <span class="sr-only">Remove</span>
            </button>
          </li>
        </ul>
      </section>
    </div>

    <!-- Confirmation dialog for date ranges with votes -->
    <BaseModal
      :open="confirmingDateRange !== null"
      title="Remove date range?"
      size="sm"
      @close="confirmingDateRange = null"
    >
      <div v-if="confirmingDateRange">
        <p class="mb-1 text-sm font-medium text-gray-900 dark:text-white">
          <DateRangeDisplay
            :start-date="confirmingDateRange.startDate"
            :end-date="confirmingDateRange.endDate"
          />
        </p>
        <p class="mb-4 text-sm text-gray-500 dark:text-stone-400">
          This date range has
          {{ confirmingDateRange.voteSummary.total }}
          {{ confirmingDateRange.voteSummary.total === 1 ? 'vote' : 'votes' }}.
          Removing it will delete all votes below.
        </p>

        <VotersList :votes="confirmingDateRange.votes" />

        <div class="mt-6 flex justify-end gap-3">
          <button
            type="button"
            autofocus
            class="rounded-md px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-100 dark:text-stone-300 dark:hover:bg-stone-700"
            @click="confirmingDateRange = null"
          >
            Cancel
          </button>
          <button
            type="button"
            :disabled="datePollsStore.loading"
            class="rounded-md bg-red-600 px-3 py-2 text-sm font-medium text-white hover:bg-red-500 disabled:opacity-50"
            @click="deleteRange(confirmingDateRange.id)"
          >
            Remove
          </button>
        </div>
      </div>
    </BaseModal>

    <DateRangeModal
      :open="showDateRangeModal"
      :preselected-start="modalPreselectedStart"
      :preselected-end="modalPreselectedEnd"
      @save="handleDateRangeModalSave"
      @close="showDateRangeModal = false"
    />
  </div>
</template>
