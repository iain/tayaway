<script setup lang="ts">
import { computed, nextTick, onMounted, ref, useId, useTemplateRef } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useChoreRostersStore } from '@/stores/choreRosters'
import { api } from '@/api/client'
import ChoreRosterGrid from '@/components/chores/ChoreRosterGrid.vue'
import ChoreRosterDayList from '@/components/chores/ChoreRosterDayList.vue'
import ChoreSummaryTable from '@/components/chores/ChoreSummaryTable.vue'
import ChoreRosterToolbar from '@/components/chores/ChoreRosterToolbar.vue'
import ChoreRosterHeader from '@/components/chores/ChoreRosterHeader.vue'
import ManageChoresSheet from '@/components/chores/ManageChoresSheet.vue'
import AssignMemberPopover from '@/components/chores/AssignMemberPopover.vue'
import EditAssignmentPopover from '@/components/chores/EditAssignmentPopover.vue'
import EditChoreTimePopover from '@/components/chores/EditChoreTimePopover.vue'
import AppButton from '@/components/common/AppButton.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import TextButton from '@/components/common/TextButton.vue'
import FormInput from '@/components/form/FormInput.vue'
import { TEXT_LIMITS } from '@/constants/limits'
import { useMediaQuery } from '@/composables/useMediaQuery'
import { useMinuteTicker } from '@/composables/useMinuteTicker'
import { ClipboardDocumentListIcon } from '@heroicons/vue/24/outline'
import type {
  PoolApiResponse,
  PoolChore,
  PoolChoreAssignment,
  PoolMember,
} from '@/types/pool'
import { can } from '@/composables/usePermission'
import {
  refillableAssignments,
  shouldSuggestAutofill,
  staleAssignmentIds,
} from '@/utils/chores'
import { enumerateDates, eventHasDates } from '@/utils/event'
import { zonedDateString } from '@/utils/timezone'

const props = withDefaults(
  defineProps<{
    eventId: string
    title: string
    subtitle?: string
    headingStyle?: 'page' | 'section'
    // Whether the phone day list scrolls to today on mount. The page owns this:
    // a lone section should scroll, but sibling sections must not fight over it.
    scrollToToday?: boolean
  }>(),
  { headingStyle: 'page', subtitle: undefined, scrollToToday: true }
)

const authStore = useAuthStore()
const pool = useObjectPoolStore()
const choreRostersStore = useChoreRostersStore()
const { currentUserId } = storeToRefs(authStore)

// On the standalone event page this section owns the <h1>, so its subheadings
// are <h2>. On /chores it sits under the event-name <h2>, so they drop to <h3>
// to keep the outline intact.
const subheadingLevel = computed(() => (props.headingStyle === 'page' ? 2 : 3))

const event = computed(() => pool.get('event', props.eventId))

const roster = computed(() => {
  return pool.getAll('choreRoster').find((r) => r.eventId === props.eventId)
})

const canDeleteRoster = computed(() => can(roster.value?.permissions, 'delete'))
const canClearAssignments = computed(() =>
  can(roster.value?.permissions, 'edit')
)

const chores = computed(() => {
  if (!roster.value) return []
  return pool
    .getAll('chore')
    .filter((c) => c.choreRosterId === roster.value!.id)
    .sort((a, b) => a.position - b.position)
})

const assignments = computed(() => {
  if (!roster.value) return []
  const choreIds = new Set(chores.value.map((c) => c.id))
  return pool.getAll('choreAssignment').filter((a) => choreIds.has(a.choreId))
})

const rsvps = computed(() => {
  return pool
    .getAll('rsvp')
    .filter((r) => r.eventId === props.eventId && r.attending)
})

const members = computed(() => {
  return pool.getAll('member')
})

const userIsAttending = computed(() => {
  if (!currentUserId.value) return false
  return rsvps.value.some((r) => r.userId === currentUserId.value)
})

const eventDates = computed(() => {
  if (!event.value?.startDate || !event.value?.endDate) return []
  return enumerateDates(event.value.startDate, event.value.endDate)
})

// Base id for this instance's add-chore form fields, so labels pair with their
// inputs even when several rosters render on /chores at once.
const formId = useId()
const nameInput = useTemplateRef<InstanceType<typeof FormInput>>('nameInput')

// The event-zone date — the same "today" the backend fences autofill and
// clear-unpinned on, so everything this page mutes, flags, or offers to
// re-fill agrees with what the server would actually touch. On the shared
// minute ticker so the fence tracks the clock while the page stays open.
const { now } = useMinuteTicker()
const today = computed(() =>
  event.value ? zonedDateString(now.value, event.value.timezone) : ''
)

const eventOver = computed(
  () => event.value?.endDate != null && event.value.endDate < today.value
)

const upcomingAssignments = computed(() =>
  assignments.value.filter((a) => a.date >= today.value)
)

// Tighter than upcoming: what a re-fill or clear would actually delete —
// today's already-started timed chores are history the server won't touch.
const refillable = computed(() =>
  event.value
    ? refillableAssignments(
        assignments.value,
        chores.value,
        today.value,
        event.value.timezone,
        now.value
      )
    : []
)

const upcomingUnpinnedCount = computed(
  () => refillable.value.filter((a) => !a.pinned).length
)

const showAddChoreForm = ref(false)
const newChoreName = ref('')
const newChorePpd = ref('1')
const newChoreTime = ref('')
const addChoreSubmitting = ref(false)
const showRsvpDialog = ref(false)
const assignPopover = ref<{
  choreId: string
  date: string
  anchorEl: HTMLElement
} | null>(null)

const editPopover = ref<{
  assignment: PoolChoreAssignment
  anchorEl: HTMLElement
} | null>(null)
const choreTimePopover = ref<{
  chore: PoolChore
  anchorEl: HTMLElement
} | null>(null)
const confirmDeleteChoreId = ref<string | null>(null)
const confirmAutofill = ref(false)
const confirmClearUpcoming = ref(false)
const confirmDeleteRoster = ref(false)
const showManageChores = ref(false)

// The roster is a dates x chores matrix on desktop and a day-first stack on the
// phone. Rendering exactly one keeps the two from ever colliding in the DOM.
const isDesktop = useMediaQuery('(min-width: 768px)')

const memberMap = computed(() => {
  const map = new Map<string, PoolMember>()
  for (const m of members.value) {
    map.set(m.userId, m)
  }
  return map
})

// Resolved live from the pool so a popover held open across a remote change
// (or a remote chore deletion) stays truthful.
const assignPopoverChore = computed(() =>
  assignPopover.value
    ? chores.value.find((c) => c.id === assignPopover.value!.choreId)
    : undefined
)

// Once the event is over there is nothing left to fill; mid-event, only the
// remaining days and their assignments say how full the fillable part is.
const suggestAutofill = computed(
  () =>
    !eventOver.value &&
    shouldSuggestAutofill(
      chores.value,
      eventDates.value.filter((d) => d >= today.value).length,
      upcomingAssignments.value.length
    )
)

// Chores whose holder isn't attending that day. Computed over the refillable
// set — a chore that already started today is history, so its holder having
// left isn't actionable. Flags chips (pinned included) via the grid/day list.
const staleIds = computed(() => {
  if (!event.value?.startDate || !event.value?.endDate || eventOver.value) {
    return new Set<string>()
  }
  return staleAssignmentIds(
    refillable.value,
    rsvps.value,
    { startDate: event.value.startDate, endDate: event.value.endDate },
    today.value
  )
})

// What the nudge's reassign button will actually move: stale and unpinned.
// A hand-pinned person stays put even when stale — their chip's warning icon
// carries that signal — so the card only appears when the button can act.
const staleUnpinnedCount = computed(
  () =>
    refillable.value.filter((a) => !a.pinned && staleIds.value.has(a.id)).length
)

const showStaleNudge = computed(
  () => !suggestAutofill.value && staleUnpinnedCount.value > 0
)

const confirmDeleteChoreName = computed(() => {
  if (!confirmDeleteChoreId.value) return ''
  const chore = chores.value.find((c) => c.id === confirmDeleteChoreId.value)
  return chore?.name ?? ''
})

const creatingRoster = ref(false)

// One-tap starters for a fresh roster — the chores nearly every trip ends up
// typing in by hand. Only offered while the roster is empty.
const CHORE_TEMPLATES = ['Cooking', 'Dishes', 'Breakfast', 'Tidy up']
const templateSubmitting = ref<string | null>(null)

async function handleAddTemplate(name: string) {
  if (!roster.value || templateSubmitting.value) return
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  templateSubmitting.value = name
  try {
    await choreRostersStore.addChore(roster.value.id, name, 1, null)
  } finally {
    templateSubmitting.value = null
  }
}

async function handleCreateRoster() {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  creatingRoster.value = true
  try {
    await choreRostersStore.createRoster(props.eventId)
  } finally {
    creatingRoster.value = false
  }
}

async function openAddChore() {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  newChoreName.value = ''
  newChorePpd.value = '1'
  newChoreTime.value = ''
  showAddChoreForm.value = true
  await nextTick()
  nameInput.value?.focus()
}

function cancelAddChore() {
  showAddChoreForm.value = false
  newChoreName.value = ''
}

async function handleAddChoreSubmit() {
  const name = newChoreName.value.trim()
  if (!name || addChoreSubmitting.value || !roster.value) return

  addChoreSubmitting.value = true
  try {
    await choreRostersStore.addChore(
      roster.value.id,
      name,
      parseInt(newChorePpd.value, 10) || 1,
      newChoreTime.value || null
    )
    newChoreName.value = ''
    newChorePpd.value = '1'
    newChoreTime.value = ''
    showAddChoreForm.value = false
  } finally {
    addChoreSubmitting.value = false
  }
}

function handleAddChoreBlur() {
  if (!newChoreName.value.trim()) {
    cancelAddChore()
  }
}

function openAssign(choreId: string, date: string, anchorEl: HTMLElement) {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  assignPopover.value = { choreId, date, anchorEl }
}

function closeAssign() {
  assignPopover.value = null
}

function openEditAssignment(
  assignment: PoolChoreAssignment,
  anchorEl: HTMLElement
) {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  editPopover.value = { assignment, anchorEl }
}

function closeEditAssignment() {
  editPopover.value = null
}

function openEditChoreTime(chore: PoolChore, anchorEl: HTMLElement) {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  choreTimePopover.value = { chore, anchorEl }
}

function closeEditChoreTime() {
  choreTimePopover.value = null
}

function handleDeleteChore(choreId: string) {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  confirmDeleteChoreId.value = choreId
}

async function confirmDeleteChoreAction() {
  if (!roster.value || !confirmDeleteChoreId.value) return
  await choreRostersStore.deleteChore(
    roster.value.id,
    confirmDeleteChoreId.value
  )
  confirmDeleteChoreId.value = null
}

function handleAutofillClick() {
  if (!roster.value) return
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  confirmAutofill.value = true
}

async function confirmAutofillAction() {
  if (!roster.value) return
  await choreRostersStore.autofill(roster.value.id)
  confirmAutofill.value = false
}

const autofillRunning = ref(false)

// The nudge cards' button. The confirm modal exists to protect existing
// unpinned assignments from being cleared; autofill only touches what's
// still refillable, so only those count — when there are none, confirming
// would just add friction, so run straight away.
async function handleNudgeAutofill() {
  if (!roster.value) return
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  if (refillable.value.some((a) => !a.pinned)) {
    confirmAutofill.value = true
  } else {
    autofillRunning.value = true
    try {
      await choreRostersStore.autofill(roster.value.id)
    } finally {
      autofillRunning.value = false
    }
  }
}

const reassignRunning = ref(false)

// The stale nudge's button: bounded to exactly the flagged chores, so it runs
// without a confirm — unlike a re-fill, it can't move anyone else's plans.
async function handleReassignStale() {
  if (!roster.value) return
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  reassignRunning.value = true
  try {
    await choreRostersStore.reassignStale(roster.value.id)
  } finally {
    reassignRunning.value = false
  }
}

function handleDeleteRoster() {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  confirmDeleteRoster.value = true
}

function handleClearUpcoming() {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  confirmClearUpcoming.value = true
}

function handleManageChores() {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  showManageChores.value = true
}

async function handleClearUpcomingConfirm() {
  if (!roster.value) return
  await choreRostersStore.clearUnpinned(roster.value.id)
  confirmClearUpcoming.value = false
}

async function handleDeleteRosterConfirm() {
  if (!roster.value) return
  await choreRostersStore.deleteRoster(roster.value.id)
  confirmDeleteRoster.value = false
}

onMounted(async () => {
  const fetches: Promise<unknown>[] = [
    api.get<PoolApiResponse>(`/events/${props.eventId}/rsvps`),
  ]

  // Try to load existing roster
  const existingRoster = pool
    .getAll('choreRoster')
    .find((r) => r.eventId === props.eventId)
  if (existingRoster) {
    fetches.push(
      api.get<PoolApiResponse>(`/chore-rosters/${existingRoster.id}`)
    )
  }

  await Promise.all(fetches)
})
</script>

<template>
  <div v-if="event" data-testid="chore-roster-section" :data-event-id="eventId">
    <div v-if="!eventHasDates(event)">
      <ChoreRosterHeader
        :title="title"
        :subtitle="subtitle"
        :heading-style="headingStyle"
      />
      <EmptyState
        :icon="ClipboardDocumentListIcon"
        :heading-level="subheadingLevel"
        heading="Dates not set"
        description="Set event dates before creating a chore roster."
      >
        <AppButton :to="`/events/${eventId}`">Go to event</AppButton>
      </EmptyState>
    </div>

    <div v-else-if="!roster">
      <ChoreRosterHeader
        :title="title"
        :subtitle="subtitle"
        :heading-style="headingStyle"
      />
      <EmptyState
        :icon="ClipboardDocumentListIcon"
        :heading-level="subheadingLevel"
        heading="No chore roster"
        description="Create a chore roster to start assigning daily tasks."
      >
        <AppButton :loading="creatingRoster" @click="handleCreateRoster">
          Create roster
        </AppButton>
      </EmptyState>
    </div>

    <div v-else>
      <ChoreRosterHeader
        :title="title"
        :subtitle="subtitle"
        :heading-style="headingStyle"
      >
        <ChoreRosterToolbar
          :can-delete="canDeleteRoster"
          :can-clear="canClearAssignments"
          @add-chore="openAddChore"
          @autofill="handleAutofillClick"
          @clear-upcoming="handleClearUpcoming"
          @delete-roster="handleDeleteRoster"
          @manage-chores="handleManageChores"
        />
      </ChoreRosterHeader>

      <div v-if="chores.length > 0">
        <BaseCard v-if="suggestAutofill" variant="action" class="mb-4 p-4">
          <div
            class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
          >
            <p class="text-ink text-sm">
              Auto-fill shares the chores fairly among everyone attending.
              Anything you assign by hand stays put.
            </p>
            <AppButton
              variant="secondary"
              class="shrink-0"
              :loading="autofillRunning"
              loading-label="Filling roster..."
              @click="handleNudgeAutofill"
            >
              Auto-fill roster
            </AppButton>
          </div>
        </BaseCard>

        <BaseCard v-if="showStaleNudge" variant="action" class="mb-4 p-4">
          <div
            class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
          >
            <p class="text-ink text-sm">
              {{
                staleUnpinnedCount === 1
                  ? '1 upcoming chore belongs to someone who isn’t there that day.'
                  : `${staleUnpinnedCount} upcoming chores belong to people who aren’t there that day.`
              }}
              Reassigning hands just
              {{ staleUnpinnedCount === 1 ? 'it' : 'them' }}
              to someone who is — everything else stays put.
            </p>
            <AppButton
              variant="secondary"
              class="shrink-0"
              :loading="reassignRunning"
              loading-label="Reassigning..."
              @click="handleReassignStale"
            >
              {{
                staleUnpinnedCount === 1
                  ? 'Reassign 1 chore'
                  : `Reassign ${staleUnpinnedCount} chores`
              }}
            </AppButton>
          </div>
        </BaseCard>

        <ChoreRosterGrid
          v-if="isDesktop"
          :chores="chores"
          :assignments="assignments"
          :dates="eventDates"
          :members="members"
          :rsvps="rsvps"
          :roster-id="roster.id"
          :current-user-id="currentUserId"
          :today="today"
          :stale-assignment-ids="staleIds"
          @assign="openAssign"
          @edit-assignment="openEditAssignment"
          @edit-chore-time="openEditChoreTime"
          @delete-chore="handleDeleteChore"
        />
        <ChoreRosterDayList
          v-else
          :chores="chores"
          :assignments="assignments"
          :dates="eventDates"
          :members="members"
          :current-user-id="currentUserId"
          :scroll-to-today="scrollToToday"
          :today="today"
          :stale-assignment-ids="staleIds"
          @assign="openAssign"
          @edit-assignment="openEditAssignment"
        />

        <ChoreSummaryTable
          v-if="assignments.length > 0"
          :chores="chores"
          :assignments="assignments"
          :members="members"
          :heading-level="subheadingLevel"
          :rsvps="rsvps"
          :event="event"
        />
      </div>

      <EmptyState
        v-else-if="!showAddChoreForm"
        :icon="ClipboardDocumentListIcon"
        :heading-level="subheadingLevel"
        heading="No chores yet"
        description="Add the usual suspects with one tap, or start from scratch."
      >
        <div class="flex flex-wrap items-center justify-center gap-2">
          <AppButton
            v-for="name in CHORE_TEMPLATES"
            :key="name"
            variant="secondary"
            :loading="templateSubmitting === name"
            @click="handleAddTemplate(name)"
          >
            {{ name }}
          </AppButton>
          <AppButton @click="openAddChore">Add chore</AppButton>
        </div>
      </EmptyState>

      <!-- Inline add chore form -->
      <div v-if="showAddChoreForm" class="mt-4">
        <form
          class="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end"
          @submit.prevent="handleAddChoreSubmit"
          @keyup.escape="cancelAddChore"
        >
          <div class="min-w-0 sm:flex-1">
            <FormInput
              :id="`${formId}-chore-name`"
              ref="nameInput"
              v-model="newChoreName"
              label="Chore name"
              placeholder="e.g. Cooking, Washing up"
              :maxlength="TEXT_LIMITS.name"
              :disabled="addChoreSubmitting"
              @blur="handleAddChoreBlur"
            />
          </div>
          <div class="flex gap-3">
            <div class="w-20 shrink-0">
              <FormInput
                :id="`${formId}-chore-ppd`"
                v-model="newChorePpd"
                label="People/day"
                type="number"
                min="1"
                max="50"
                :disabled="addChoreSubmitting"
              />
            </div>
            <div class="w-28 shrink-0">
              <FormInput
                :id="`${formId}-chore-time`"
                v-model="newChoreTime"
                label="Time (optional)"
                type="time"
                :disabled="addChoreSubmitting"
              />
            </div>
          </div>
          <AppButton
            type="submit"
            class="w-full sm:w-auto"
            :disabled="!newChoreName.trim()"
            :loading="addChoreSubmitting"
            loading-label="Adding..."
          >
            Add
          </AppButton>
        </form>
      </div>

      <AssignMemberPopover
        v-if="assignPopover && assignPopoverChore"
        :chore="assignPopoverChore"
        :date="assignPopover.date"
        :anchor-el="assignPopover.anchorEl"
        :roster-id="roster.id"
        :members="members"
        :rsvps="rsvps"
        :assignments="assignments"
        :event="event"
        :current-user-id="currentUserId"
        @close="closeAssign"
      />

      <EditAssignmentPopover
        v-if="editPopover"
        :assignment="editPopover.assignment"
        :anchor-el="editPopover.anchorEl"
        :roster-id="roster.id"
        :member-map="memberMap"
        :assignments="assignments"
        :rsvps="rsvps"
        :event="event"
        @close="closeEditAssignment"
      />

      <EditChoreTimePopover
        v-if="choreTimePopover"
        :chore="choreTimePopover.chore"
        :anchor-el="choreTimePopover.anchorEl"
        :roster-id="roster.id"
        @close="closeEditChoreTime"
      />

      <ManageChoresSheet
        v-if="showManageChores"
        :open="showManageChores"
        :chores="chores"
        :roster-id="roster.id"
        @close="showManageChores = false"
      />
    </div>

    <BaseModal
      :open="confirmDeleteChoreId != null"
      title="Delete chore"
      size="sm"
      @close="confirmDeleteChoreId = null"
    >
      <p class="text-ink-muted text-sm">
        Delete "{{ confirmDeleteChoreName }}"? This will remove all its
        assignments.
      </p>
      <div class="mt-6 flex justify-end gap-3">
        <TextButton variant="secondary" @click="confirmDeleteChoreId = null">
          Cancel
        </TextButton>
        <AppButton variant="danger" autofocus @click="confirmDeleteChoreAction">
          Delete
        </AppButton>
      </div>
    </BaseModal>

    <BaseModal
      :open="confirmAutofill"
      title="Auto-fill roster"
      size="sm"
      @close="confirmAutofill = false"
    >
      <p class="text-ink-muted text-sm">
        <template v-if="upcomingUnpinnedCount > 0">
          This will reassign
          {{ upcomingUnpinnedCount }} upcoming assignment{{
            upcomingUnpinnedCount === 1 ? '' : 's'
          }}
          and redistribute what's still ahead fairly among attendees.
        </template>
        <template v-else>
          This will fill the open slots fairly among attendees.
        </template>
        Days already past, chores that have already started today, and pinned
        assignments stay as they are.
      </p>
      <div class="mt-6 flex justify-end gap-3">
        <TextButton variant="secondary" @click="confirmAutofill = false">
          Cancel
        </TextButton>
        <AppButton autofocus @click="confirmAutofillAction">
          Auto-fill
        </AppButton>
      </div>
    </BaseModal>

    <BaseModal
      :open="confirmClearUpcoming"
      title="Clear upcoming assignments"
      size="sm"
      @close="confirmClearUpcoming = false"
    >
      <p class="text-ink-muted text-sm">
        <template v-if="upcomingUnpinnedCount > 0">
          This clears
          {{ upcomingUnpinnedCount }} upcoming assignment{{
            upcomingUnpinnedCount === 1 ? '' : 's'
          }}. Days already past, chores that have already started today, and
          pinned assignments stay as they are.
        </template>
        <template v-else>
          There's nothing to clear — no upcoming assignments are unpinned.
        </template>
      </p>
      <div class="mt-6 flex justify-end gap-3">
        <TextButton variant="secondary" @click="confirmClearUpcoming = false">
          Cancel
        </TextButton>
        <AppButton
          :disabled="upcomingUnpinnedCount === 0"
          autofocus
          @click="handleClearUpcomingConfirm"
        >
          Clear
        </AppButton>
      </div>
    </BaseModal>

    <BaseModal
      :open="confirmDeleteRoster"
      title="Delete roster"
      size="sm"
      @close="confirmDeleteRoster = false"
    >
      <p class="text-ink-muted text-sm">
        This deletes the whole roster — every chore and assignment, including
        the record of days already done. This can't be undone.
      </p>
      <div class="mt-6 flex justify-end gap-3">
        <TextButton variant="secondary" @click="confirmDeleteRoster = false">
          Cancel
        </TextButton>
        <AppButton
          variant="danger"
          autofocus
          @click="handleDeleteRosterConfirm"
        >
          Delete roster
        </AppButton>
      </div>
    </BaseModal>

    <BaseModal
      :open="showRsvpDialog"
      title="RSVP required"
      size="sm"
      @close="showRsvpDialog = false"
    >
      <p class="text-ink-muted text-sm">
        You need to RSVP as attending before you can manage chores.
      </p>
      <div class="mt-6 flex justify-end gap-3">
        <TextButton variant="secondary" @click="showRsvpDialog = false">
          Cancel
        </TextButton>
        <AppButton
          :to="`/events/${eventId}/rsvp`"
          autofocus
          @click="showRsvpDialog = false"
        >
          Go to RSVP
        </AppButton>
      </div>
    </BaseModal>
  </div>

  <div v-else class="text-ink-muted">Event not found</div>
</template>
