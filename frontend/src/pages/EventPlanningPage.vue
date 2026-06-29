<script setup lang="ts">
import { computed, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowDownTrayIcon,
  ArrowPathIcon,
  CalendarDaysIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useDatePollsStore } from '@/stores/datePolls'
import { useEventsStore } from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollActive, isPollResolved } from '@/utils/poll'
import { eventHasDates } from '@/utils/event'
import { generateIcs, downloadIcs } from '@/utils/ics'
import DatePollSection from '@/components/events/DatePollSection.vue'
import AwaitingVotesSection from '@/components/events/AwaitingVotesSection.vue'
import OpenPollModal from '@/components/events/OpenPollModal.vue'
import RsvpSection from '@/components/events/RsvpSection.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import { can } from '@/composables/usePermission'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()
const datePollsStore = useDatePollsStore()
const eventsStore = useEventsStore()
const pool = useObjectPoolStore()
const { currentUserId } = storeToRefs(authStore)
const { loading: eventLoading } = storeToRefs(eventsStore)

const showPollModal = ref(false)
const pollModalMode = ref<'open' | 'reopen'>('open')

const eventId = computed(() => route.params.id as string)

const { event } = useHydratedEvent(eventId)

const canCreatePoll = computed(() =>
  can(event.value?.permissions, 'create_poll')
)
const canEditEvent = computed(() => can(event.value?.permissions, 'edit'))

const eventHasStarted = computed(() => {
  const sd = event.value?.startDate
  return !!sd && sd < new Date().toISOString().slice(0, 10)
})

const canOpenOrReopenPoll = computed(() => {
  return canCreatePoll.value && !!event.value && !eventHasStarted.value
})

// The page is one phase-driven hub: an open poll means we're still picking
// dates (vote), confirmed dates mean we're collecting RSVPs, and neither means
// the dates haven't been started yet.
const pollActive = computed(() => isPollActive(event.value?.datePoll))
const pollResolved = computed(() => isPollResolved(event.value?.datePoll))
const hasDates = computed(() =>
  event.value ? eventHasDates(event.value) : false
)

const headerTitle = computed(() => {
  if (pollActive.value) return 'Date poll'
  else if (hasDates.value) return 'RSVP'
  else return 'Dates'
})
const headerIcon = computed(() =>
  !pollActive.value && hasDates.value ? UserGroupIcon : CalendarDaysIcon
)

function handleVote(): void {
  router.push(`/events/${eventId.value}/planning/vote`)
}

function handleOpenPoll(): void {
  pollModalMode.value = 'open'
  showPollModal.value = true
}

function handleReopenPoll(): void {
  pollModalMode.value = 'reopen'
  showPollModal.value = true
}

async function handlePollModalConfirm(deadline: string): Promise<void> {
  try {
    if (pollModalMode.value === 'reopen') {
      await datePollsStore.reopenPoll(eventId.value, deadline)
    } else {
      await datePollsStore.createPoll(eventId.value, deadline)
      router.push(`/events/${eventId.value}/planning/date-ranges`)
    }
    showPollModal.value = false
  } catch {
    // Error handled by store
  }
}

// Inline date editing — the shortcut for setting dates without running a poll.
const datesBlockedOpen = ref(false)
const showDateForm = ref(false)
const editStartDate = ref('')
const editEndDate = ref('')

const hasExpenses = computed(() => {
  return pool.getAll('expense').some((e) => e.eventId === eventId.value)
})

function openDatesEdit(): void {
  if (hasExpenses.value) {
    datesBlockedOpen.value = true
    return
  }
  editStartDate.value = event.value?.startDate ?? ''
  editEndDate.value = event.value?.endDate ?? ''
  showDateForm.value = true
}

async function saveDates(): Promise<void> {
  if (!event.value || eventLoading.value) return
  await eventsStore.updateEvent(eventId.value, {
    name: event.value.name,
    startDate: editStartDate.value || undefined,
    endDate: editEndDate.value || undefined,
  })
  showDateForm.value = false
}

function handleDownloadIcs(): void {
  if (!event.value) return
  const e = event.value
  const content = generateIcs({
    uid: e.id,
    summary: e.name,
    description: e.description,
    startDate: e.startDate,
    endDate: e.endDate,
    location: e.locationName,
    createdAt: e.createdAt,
  })
  const filename =
    e.name
      .replace(/[^a-z0-9]+/gi, '-')
      .replace(/^-|-$/g, '')
      .toLowerCase() + '.ics'
  downloadIcs(filename, content)
}
</script>

<template>
  <div>
    <div v-if="!event" class="text-ink-muted">Event not found</div>

    <div v-else>
      <PageHeader :title="headerTitle" size="sm" :icon="headerIcon" />

      <!-- Poll open/expired: vote on the dates -->
      <div v-if="pollActive" class="grid gap-6 lg:grid-cols-2">
        <DatePollSection
          :event="event"
          :is-owner="canCreatePoll"
          :current-user-id="currentUserId"
          @vote="handleVote"
        />
        <AwaitingVotesSection
          v-if="event.datePoll!.dateRanges.length > 0"
          :event="event"
          :current-user-id="currentUserId"
        />
      </div>

      <!-- Dates confirmed: RSVP -->
      <template v-else-if="hasDates">
        <RsvpSection :event="event" :current-user-id="currentUserId" />
        <TextButton class="mt-4" @click="handleDownloadIcs">
          <ArrowDownTrayIcon class="size-4" />
          Add to calendar
        </TextButton>

        <!-- Owner: revisit the dates with a fresh or reopened poll -->
        <div v-if="canOpenOrReopenPoll" class="border-line mt-8 border-t pt-6">
          <AppButton
            v-if="pollResolved"
            variant="secondary"
            @click="handleReopenPoll"
          >
            <ArrowPathIcon class="size-4" />
            Reopen Poll
          </AppButton>
          <template v-else>
            <p class="text-ink-muted max-w-sm text-sm">
              Need to reconsider? Opening a date poll lets members vote on
              alternatives. When you close the poll, the winning dates will
              replace the current ones and RSVPs will be reset.
            </p>
            <AppButton variant="secondary" class="mt-3" @click="handleOpenPoll">
              Open Date Poll
            </AppButton>
          </template>
        </div>
        <p
          v-else-if="pollResolved && canCreatePoll && eventHasStarted"
          class="text-ink-muted mt-8 text-sm"
        >
          The poll can't be reopened because the event has already started.
        </p>
      </template>

      <!-- No poll, no dates: open a poll or set dates directly -->
      <EmptyState
        v-else
        :icon="CalendarDaysIcon"
        heading="No dates yet"
        description="Open a date poll to let members vote on when to go. You propose date options, everyone votes, then you pick the winner."
      >
        <div class="flex flex-col items-center gap-3">
          <AppButton v-if="canOpenOrReopenPoll" @click="handleOpenPoll">
            Open Date Poll
          </AppButton>
          <p
            v-if="canCreatePoll && eventHasStarted"
            class="text-ink-muted text-sm"
          >
            A date poll can't be opened because the event has already started.
          </p>

          <template v-if="canEditEvent">
            <form
              v-if="showDateForm"
              class="flex flex-wrap items-end justify-center gap-3"
              @submit.prevent="saveDates"
            >
              <div>
                <label
                  for="event-start-date"
                  class="text-ink-muted mb-1 block text-xs font-medium"
                >
                  Start date
                </label>
                <input
                  id="event-start-date"
                  v-model="editStartDate"
                  type="date"
                  :disabled="eventLoading"
                  class="bg-surface-sunken text-ink outline-line focus:outline-focus rounded-md px-3 py-1.5 text-sm outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 dark:[color-scheme:dark]"
                />
              </div>
              <div>
                <label
                  for="event-end-date"
                  class="text-ink-muted mb-1 block text-xs font-medium"
                >
                  End date
                </label>
                <input
                  id="event-end-date"
                  v-model="editEndDate"
                  type="date"
                  :disabled="eventLoading"
                  class="bg-surface-sunken text-ink outline-line focus:outline-focus rounded-md px-3 py-1.5 text-sm outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 dark:[color-scheme:dark]"
                />
              </div>
              <AppButton type="submit" size="sm" :loading="eventLoading">
                Save
              </AppButton>
              <TextButton
                variant="secondary"
                :disabled="eventLoading"
                @click="showDateForm = false"
              >
                Cancel
              </TextButton>
            </form>
            <TextButton v-else variant="secondary" @click="openDatesEdit">
              or set dates directly
            </TextButton>
          </template>
        </div>
      </EmptyState>

      <BaseModal
        :open="datesBlockedOpen"
        title="Can't change dates"
        @close="datesBlockedOpen = false"
      >
        <p class="text-ink-muted">
          This event has expenses tied to the current dates. Delete or adjust
          the expenses first, then you can change the event dates.
        </p>
        <div class="mt-6 flex justify-end">
          <AppButton variant="secondary" @click="datesBlockedOpen = false">
            Got it
          </AppButton>
        </div>
      </BaseModal>
    </div>
  </div>

  <OpenPollModal
    :open="showPollModal"
    :title="pollModalMode === 'reopen' ? 'Reopen Date Poll' : 'Open Date Poll'"
    :loading="datePollsStore.loading"
    :autofocus-submit="pollModalMode === 'reopen'"
    @confirm="handlePollModalConfirm"
    @close="showPollModal = false"
  />
</template>
