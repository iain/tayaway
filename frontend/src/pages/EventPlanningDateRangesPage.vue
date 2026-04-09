<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { PlusIcon, TrashIcon } from '@heroicons/vue/24/outline'
import { useDatePollsStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import type { HydratedDateRange } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'
import DateRangeModal from '@/components/events/DateRangeModal.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import VotersList from '@/components/votes/VotersList.vue'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import { useDateRangeActions } from '@/composables/useDateRangeActions'
import { can } from '@/composables/usePermission'

const route = useRoute()
const { pendingAdd: pendingAddDateRange, resetAdd: resetAddDateRange } =
  useDateRangeActions()
const datePollsStore = useDatePollsStore()
const { addDays } = useCalendar()

const eventId = computed(() => route.params.id as string)

const { event } = useHydratedEvent(eventId)

const showDateRangeModal = ref(false)
const modalPreselectedStart = ref<string | null>(null)
const modalPreselectedEnd = ref<string | null>(null)

const confirmingDateRange = ref<HydratedDateRange | null>(null)

const canManageDateRanges = computed(() =>
  can(event.value?.permissions, 'create_poll')
)

const dateRanges = computed(() => {
  return event.value?.datePoll?.dateRanges ?? []
})

watch(pendingAddDateRange, (val) => {
  if (val) {
    resetAddDateRange()
    handleAddDateRange()
  }
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
      <PageHeader title="Edit Date Ranges" size="sm" />

      <section>
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
            Date Options
          </h2>
          <AppButton
            v-if="canManageDateRanges"
            :disabled="datePollsStore.loading"
            @click="handleAddDateRange"
          >
            <PlusIcon class="size-4" />
            Add Date Range
          </AppButton>
        </div>

        <div v-if="dateRanges.length === 0" class="py-12 text-center">
          <p class="mb-4 text-gray-500 dark:text-stone-400">
            No date ranges added yet.
          </p>
          <AppButton
            v-if="canManageDateRanges"
            :disabled="datePollsStore.loading"
            @click="handleAddDateRange"
          >
            <PlusIcon class="size-4" />
            Add Date Range
          </AppButton>
        </div>

        <ul v-else class="space-y-3">
          <BaseCard
            v-for="dateRange in dateRanges"
            :key="dateRange.id"
            as="li"
            class="flex items-center justify-between px-4 py-3"
            data-testid="date-range-item"
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
            <IconButton
              v-if="canManageDateRanges"
              variant="danger"
              label="Remove"
              :disabled="datePollsStore.loading"
              class="ml-4"
              @click="handleDeleteClick(dateRange)"
            >
              <TrashIcon class="size-4" />
            </IconButton>
          </BaseCard>
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
          <AppButton
            variant="secondary"
            autofocus
            @click="confirmingDateRange = null"
          >
            Cancel
          </AppButton>
          <AppButton
            variant="danger"
            :disabled="datePollsStore.loading"
            @click="deleteRange(confirmingDateRange.id)"
          >
            Remove
          </AppButton>
        </div>
      </div>
    </BaseModal>

    <DateRangeModal
      :open="showDateRangeModal"
      :preselected-start="modalPreselectedStart"
      :preselected-end="modalPreselectedEnd"
      :existing-ranges="
        dateRanges.map((r) => ({
          start_date: r.startDate,
          end_date: r.endDate,
        }))
      "
      @save="handleDateRangeModalSave"
      @close="showDateRangeModal = false"
    />
  </div>
</template>
