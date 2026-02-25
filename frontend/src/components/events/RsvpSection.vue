<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  CheckCircleIcon,
  XCircleIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/solid'
import { UserIcon, CalendarDaysIcon } from '@heroicons/vue/24/outline'
import { useRsvpsStore } from '@/stores/rsvps'
import type { HydratedEvent } from '@/composables/useHydratedEvent'
import SectionHeading from '@/components/common/SectionHeading.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import TextButton from '@/components/common/TextButton.vue'

const props = defineProps<{
  event: HydratedEvent
  currentUserId: string | null
}>()

const rsvpsStore = useRsvpsStore()

const showPartialPicker = ref(false)
const partialStartDate = ref('')
const partialEndDate = ref('')

const currentUserRsvp = computed(() => {
  if (!props.currentUserId) return undefined
  return props.event.rsvps.find((r) => r.userId === props.currentUserId)
})

const isEventInPast = computed(() => {
  if (!props.event.endDate) return false
  return props.event.endDate < new Date().toISOString().slice(0, 10)
})

const attending = computed(() => props.event.rsvps.filter((r) => r.attending))

const notAttending = computed(() =>
  props.event.rsvps.filter((r) => !r.attending)
)

const noResponse = computed(() => {
  if (!props.event.workspace) return []
  const rsvpUserIds = new Set(props.event.rsvps.map((r) => r.userId))
  return props.event.workspace.members.filter((m) => !rsvpUserIds.has(m.userId))
})

async function handleAttend(): Promise<void> {
  try {
    await rsvpsStore.submitRsvp(props.event.id, true)
  } catch {
    // Error handled by store
  }
}

async function handleDecline(): Promise<void> {
  try {
    await rsvpsStore.submitRsvp(props.event.id, false)
  } catch {
    // Error handled by store
  }
}

function openPartialPicker(): void {
  partialStartDate.value = props.event.startDate ?? ''
  partialEndDate.value = props.event.endDate ?? ''
  showPartialPicker.value = true
}

async function handleSavePartialDates(): Promise<void> {
  try {
    await rsvpsStore.submitRsvp(
      props.event.id,
      true,
      partialStartDate.value,
      partialEndDate.value
    )
    showPartialPicker.value = false
  } catch {
    // Error handled by store
  }
}

async function handleClearPartialDates(): Promise<void> {
  try {
    await rsvpsStore.submitRsvp(props.event.id, true)
    showPartialPicker.value = false
  } catch {
    // Error handled by store
  }
}
</script>

<template>
  <BaseCard as="section" padded data-testid="rsvp-section">
    <SectionHeading :icon="UserGroupIcon" title="RSVPs" />

    <!-- Current user RSVP toggle -->
    <div class="mb-6">
      <p class="mb-2 text-sm font-medium text-gray-700 dark:text-stone-300">
        Your response
      </p>

      <!-- Past event notice -->
      <p v-if="isEventInPast" class="text-sm text-gray-500 dark:text-stone-400">
        This event has already ended.
      </p>

      <template v-else>
        <div class="flex gap-2">
          <button
            type="button"
            data-testid="rsvp-attend"
            :aria-pressed="currentUserRsvp?.attending ? 'true' : 'false'"
            class="inline-flex items-center gap-2 rounded-md px-4 py-2 text-sm font-semibold shadow-sm"
            :class="
              currentUserRsvp?.attending
                ? 'bg-green-600 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-stone-600'
            "
            @click="handleAttend"
          >
            <CheckCircleIcon class="size-4" />
            Attending
          </button>
          <button
            type="button"
            data-testid="rsvp-decline"
            :aria-pressed="
              currentUserRsvp && !currentUserRsvp.attending ? 'true' : 'false'
            "
            class="inline-flex items-center gap-2 rounded-md px-4 py-2 text-sm font-semibold shadow-sm"
            :class="
              currentUserRsvp && !currentUserRsvp.attending
                ? 'bg-red-600 text-white'
                : 'bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-stone-600'
            "
            @click="handleDecline"
          >
            <XCircleIcon class="size-4" />
            Not Attending
          </button>
        </div>

        <!-- Partial attendance -->
        <div v-if="currentUserRsvp?.attending" class="mt-3">
          <div v-if="currentUserRsvp.startDate && currentUserRsvp.endDate">
            <p class="text-sm text-gray-600 dark:text-stone-400">
              <CalendarDaysIcon class="inline size-4" />
              <DateRangeDisplay
                :start-date="currentUserRsvp.startDate"
                :end-date="currentUserRsvp.endDate"
              />
              (partial)
            </p>
          </div>
          <TextButton
            v-if="!showPartialPicker"
            data-testid="rsvp-change-dates"
            class="mt-1"
            @click="openPartialPicker"
          >
            {{
              currentUserRsvp.startDate ? 'Change dates' : 'Set partial dates'
            }}
          </TextButton>

          <!-- Partial date picker -->
          <div
            v-if="showPartialPicker"
            class="mt-3 rounded-md border border-gray-200 p-3 dark:border-stone-600"
          >
            <p
              class="mb-2 text-sm font-medium text-gray-700 dark:text-stone-300"
            >
              Your attendance dates
            </p>
            <div class="flex items-center gap-2">
              <input
                v-model="partialStartDate"
                type="date"
                :min="event.startDate ?? undefined"
                :max="event.endDate ?? undefined"
                class="rounded-md border border-gray-300 px-2 py-1 text-sm dark:border-stone-600 dark:bg-stone-700 dark:text-white"
              />
              <span class="text-gray-500 dark:text-stone-400">to</span>
              <input
                v-model="partialEndDate"
                type="date"
                :min="event.startDate ?? undefined"
                :max="event.endDate ?? undefined"
                class="rounded-md border border-gray-300 px-2 py-1 text-sm dark:border-stone-600 dark:bg-stone-700 dark:text-white"
              />
            </div>
            <div class="mt-2 flex gap-2">
              <button
                type="button"
                class="rounded-md bg-rose-600 px-3 py-1 text-sm font-semibold text-white hover:bg-rose-500"
                @click="handleSavePartialDates"
              >
                Save
              </button>
              <button
                v-if="currentUserRsvp.startDate"
                type="button"
                class="rounded-md bg-gray-100 px-3 py-1 text-sm font-medium text-gray-700 hover:bg-gray-200 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-stone-600"
                @click="handleClearPartialDates"
              >
                Full event
              </button>
              <button
                type="button"
                class="rounded-md px-3 py-1 text-sm text-gray-500 hover:text-gray-700 dark:text-stone-400 dark:hover:text-stone-300"
                @click="showPartialPicker = false"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- Attendee lists -->
    <div class="space-y-4">
      <!-- Attending -->
      <div v-if="attending.length > 0">
        <h3 class="mb-2 text-sm font-medium text-green-600 dark:text-green-400">
          Attending ({{ attending.length }})
        </h3>
        <ul class="space-y-2">
          <li
            v-for="rsvp in attending"
            :key="rsvp.id"
            class="flex items-center gap-3 rounded-md bg-green-50 px-3 py-2 dark:bg-green-900/20"
          >
            <div
              class="flex size-8 items-center justify-center rounded-full bg-green-200 dark:bg-green-800"
            >
              <CheckCircleIcon
                class="size-4 text-green-600 dark:text-green-400"
              />
            </div>
            <div>
              <span class="text-gray-900 dark:text-white">
                {{ rsvp.member?.name || rsvp.member?.email || 'Unknown' }}
                <span
                  v-if="rsvp.userId === currentUserId"
                  class="text-sm text-green-600 dark:text-green-400"
                >
                  (you)
                </span>
              </span>
              <p
                v-if="rsvp.startDate && rsvp.endDate"
                class="text-xs text-gray-500 dark:text-stone-400"
              >
                <DateRangeDisplay
                  :start-date="rsvp.startDate"
                  :end-date="rsvp.endDate"
                />
              </p>
            </div>
          </li>
        </ul>
      </div>

      <!-- Not attending -->
      <div v-if="notAttending.length > 0">
        <h3 class="mb-2 text-sm font-medium text-red-600 dark:text-red-400">
          Not Attending ({{ notAttending.length }})
        </h3>
        <ul class="space-y-2">
          <li
            v-for="rsvp in notAttending"
            :key="rsvp.id"
            class="flex items-center gap-3 rounded-md bg-red-50 px-3 py-2 dark:bg-red-900/20"
          >
            <div
              class="flex size-8 items-center justify-center rounded-full bg-red-200 dark:bg-red-800"
            >
              <XCircleIcon class="size-4 text-red-600 dark:text-red-400" />
            </div>
            <span class="text-gray-900 dark:text-white">
              {{ rsvp.member?.name || rsvp.member?.email || 'Unknown' }}
              <span
                v-if="rsvp.userId === currentUserId"
                class="text-sm text-red-600 dark:text-red-400"
              >
                (you)
              </span>
            </span>
          </li>
        </ul>
      </div>

      <!-- No response -->
      <div v-if="noResponse.length > 0">
        <h3 class="mb-2 text-sm font-medium text-gray-500 dark:text-stone-400">
          No Response ({{ noResponse.length }})
        </h3>
        <ul class="space-y-2">
          <li
            v-for="member in noResponse"
            :key="member.id"
            class="flex items-center gap-3 rounded-md bg-gray-50 px-3 py-2 dark:bg-stone-700/50"
          >
            <div
              class="flex size-8 items-center justify-center rounded-full bg-gray-200 dark:bg-stone-600"
            >
              <UserIcon class="size-4 text-gray-500 dark:text-stone-400" />
            </div>
            <span class="text-gray-900 dark:text-white">
              {{ member.name || member.email || 'Unknown' }}
              <span
                v-if="member.userId === currentUserId"
                class="text-sm text-amber-600 dark:text-amber-400"
              >
                (you)
              </span>
            </span>
          </li>
        </ul>
      </div>

      <!-- Summary -->
      <p
        v-if="event.rsvps.length > 0"
        class="text-sm text-gray-500 dark:text-stone-400"
      >
        {{ attending.length }} attending, {{ notAttending.length }} not
        attending, {{ noResponse.length }} pending
      </p>
    </div>
  </BaseCard>
</template>
