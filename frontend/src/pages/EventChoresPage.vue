<script setup lang="ts">
import { computed, nextTick, onMounted, ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useChoreRostersStore } from '@/stores/choreRosters'
import { api } from '@/api/client'
import ChoreRosterGrid from '@/components/chores/ChoreRosterGrid.vue'
import ChoreSummaryTable from '@/components/chores/ChoreSummaryTable.vue'
import ChoreRosterToolbar from '@/components/chores/ChoreRosterToolbar.vue'
import AssignMemberPopover from '@/components/chores/AssignMemberPopover.vue'
import EditAssignmentPopover from '@/components/chores/EditAssignmentPopover.vue'
import AppButton from '@/components/common/AppButton.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import TextButton from '@/components/common/TextButton.vue'
import { ClipboardDocumentListIcon } from '@heroicons/vue/24/outline'
import type {
  PoolApiResponse,
  PoolChoreAssignment,
  PoolMember,
} from '@/types/pool'
import { can } from '@/composables/usePermission'

const route = useRoute()
const authStore = useAuthStore()
const pool = useObjectPoolStore()
const choreRostersStore = useChoreRostersStore()
const { currentUserId } = storeToRefs(authStore)

const eventId = computed(() => route.params.id as string)
const event = computed(() => pool.get('event', eventId.value))

const roster = computed(() => {
  return pool.getAll('choreRoster').find((r) => r.eventId === eventId.value)
})

const canDeleteRoster = computed(() => can(roster.value?.permissions, 'delete'))

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
    .filter((r) => r.eventId === eventId.value && r.attending)
})

const members = computed(() => {
  return pool.getAll('member')
})

const userIsAttending = computed(() => {
  if (!currentUserId.value) return false
  return rsvps.value.some((r) => r.userId === currentUserId.value)
})

const eventHasDates = computed(
  () => event.value?.startDate != null && event.value?.endDate != null
)

const eventDates = computed(() => {
  if (!event.value?.startDate || !event.value?.endDate) return []
  const start = new Date(event.value.startDate)
  const end = new Date(event.value.endDate)
  const dates: string[] = []
  const d = new Date(start)
  while (d <= end) {
    dates.push(d.toISOString().slice(0, 10))
    d.setDate(d.getDate() + 1)
  }
  return dates
})

const showAddChoreForm = ref(false)
const newChoreName = ref('')
const newChorePpd = ref('1')
const addChoreInput = ref<HTMLInputElement | null>(null)
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
const confirmDeleteChoreId = ref<string | null>(null)
const confirmAutofill = ref(false)
const showDeleteActions = ref(false)

const memberMap = computed(() => {
  const map = new Map<string, PoolMember>()
  for (const m of members.value) {
    map.set(m.userId, m)
  }
  return map
})

const confirmDeleteChoreName = computed(() => {
  if (!confirmDeleteChoreId.value) return ''
  const chore = chores.value.find((c) => c.id === confirmDeleteChoreId.value)
  return chore?.name ?? ''
})

const creatingRoster = ref(false)

async function handleCreateRoster() {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  creatingRoster.value = true
  try {
    await choreRostersStore.createRoster(eventId.value)
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
  showAddChoreForm.value = true
  await nextTick()
  addChoreInput.value?.focus()
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
      parseInt(newChorePpd.value, 10) || 1
    )
    newChoreName.value = ''
    newChorePpd.value = '1'
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

function handleDeleteRoster() {
  if (!userIsAttending.value) {
    showRsvpDialog.value = true
    return
  }
  showDeleteActions.value = true
}

async function handleClearUnpinned() {
  if (!roster.value) return
  await choreRostersStore.clearUnpinned(roster.value.id)
  showDeleteActions.value = false
}

async function handleDeleteRosterConfirm() {
  if (!roster.value) return
  await choreRostersStore.deleteRoster(roster.value.id)
  showDeleteActions.value = false
}

onMounted(async () => {
  const fetches: Promise<unknown>[] = [
    api.get<PoolApiResponse>(`/events/${eventId.value}/rsvps`),
  ]

  // Try to load existing roster
  const existingRoster = pool
    .getAll('choreRoster')
    .find((r) => r.eventId === eventId.value)
  if (existingRoster) {
    fetches.push(
      api.get<PoolApiResponse>(`/chore-rosters/${existingRoster.id}`)
    )
  }

  await Promise.all(fetches)
})
</script>

<template>
  <div>
    <div v-if="!event" class="text-gray-500 dark:text-stone-400">
      Event not found
    </div>

    <div v-else-if="!eventHasDates">
      <EmptyState
        :icon="ClipboardDocumentListIcon"
        heading="Dates not set"
        description="Set event dates before creating a chore roster."
      >
        <AppButton :to="`/events/${eventId}`">Go to event</AppButton>
      </EmptyState>
    </div>

    <div v-else-if="!roster">
      <EmptyState
        :icon="ClipboardDocumentListIcon"
        heading="No chore roster"
        description="Create a chore roster to start assigning daily tasks."
      >
        <AppButton :loading="creatingRoster" @click="handleCreateRoster">
          Create roster
        </AppButton>
      </EmptyState>
    </div>

    <div v-else>
      <PageHeader
        title="Chores"
        size="sm"
        :icon="ClipboardDocumentListIcon"
      >
        <ChoreRosterToolbar
          :can-delete="canDeleteRoster"
          @add-chore="openAddChore"
          @autofill="handleAutofillClick"
          @delete-roster="handleDeleteRoster"
        />
      </PageHeader>

      <div v-if="chores.length > 0">
        <ChoreRosterGrid
          :chores="chores"
          :assignments="assignments"
          :dates="eventDates"
          :members="members"
          :rsvps="rsvps"
          :roster-id="roster.id"
          :current-user-id="currentUserId"
          @assign="openAssign"
          @edit-assignment="openEditAssignment"
          @delete-chore="handleDeleteChore"
        />

        <ChoreSummaryTable
          v-if="assignments.length > 0"
          :chores="chores"
          :assignments="assignments"
          :members="members"
        />
      </div>

      <EmptyState
        v-else-if="!showAddChoreForm"
        :icon="ClipboardDocumentListIcon"
        heading="No chores yet"
        description="Add your first chore to start building the roster."
      >
        <AppButton @click="openAddChore">Add chore</AppButton>
      </EmptyState>

      <!-- Inline add chore form -->
      <div v-if="showAddChoreForm" class="mt-4">
        <form
          class="flex items-end gap-3"
          @submit.prevent="handleAddChoreSubmit"
        >
          <div class="min-w-0 flex-1">
            <label
              for="new-chore-name"
              class="mb-1 block text-xs font-medium text-gray-500 dark:text-stone-400"
            >
              Chore name
            </label>
            <input
              id="new-chore-name"
              ref="addChoreInput"
              v-model="newChoreName"
              type="text"
              placeholder="e.g. Cooking, Washing up"
              class="w-full rounded-md bg-gray-100 px-3 py-2 text-sm font-semibold text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:font-normal placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-focus dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
              :maxlength="255"
              :disabled="addChoreSubmitting"
              @keyup.escape="cancelAddChore"
              @blur="handleAddChoreBlur"
            />
          </div>
          <div class="w-20 shrink-0">
            <label
              for="new-chore-ppd"
              class="mb-1 block text-xs font-medium text-gray-500 dark:text-stone-400"
            >
              People/day
            </label>
            <input
              id="new-chore-ppd"
              v-model="newChorePpd"
              type="number"
              min="1"
              max="50"
              class="w-full rounded-md bg-gray-100 px-3 py-2 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-focus dark:bg-white/5 dark:text-white dark:outline-white/10"
              :disabled="addChoreSubmitting"
              @keyup.escape="cancelAddChore"
            />
          </div>
          <AppButton
            type="submit"
            size="sm"
            :disabled="!newChoreName.trim()"
            :loading="addChoreSubmitting"
            loading-label="Adding..."
          >
            Add
          </AppButton>
        </form>
      </div>

      <AssignMemberPopover
        v-if="assignPopover"
        :chore-id="assignPopover.choreId"
        :date="assignPopover.date"
        :anchor-el="assignPopover.anchorEl"
        :roster-id="roster.id"
        :members="members"
        :rsvps="rsvps"
        :assignments="assignments"
        :event="event"
        @close="closeAssign"
      />

      <EditAssignmentPopover
        v-if="editPopover"
        :assignment="editPopover.assignment"
        :anchor-el="editPopover.anchorEl"
        :roster-id="roster.id"
        :member-map="memberMap"
        @close="closeEditAssignment"
      />
    </div>

    <BaseModal
      :open="confirmDeleteChoreId != null"
      title="Delete chore"
      size="sm"
      @close="confirmDeleteChoreId = null"
    >
      <p class="text-sm text-gray-600 dark:text-stone-400">
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
      <p class="text-sm text-gray-600 dark:text-stone-400">
        This will clear all non-pinned assignments and redistribute them fairly
        among attendees. Pinned assignments stay as they are.
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
      :open="showDeleteActions"
      title="Manage roster"
      size="sm"
      @close="showDeleteActions = false"
    >
      <div class="flex flex-col gap-3">
        <AppButton variant="secondary" @click="handleClearUnpinned">
          Clear non-pinned assignments
        </AppButton>
        <AppButton variant="danger" @click="handleDeleteRosterConfirm">
          Delete entire roster
        </AppButton>
      </div>
    </BaseModal>

    <BaseModal
      :open="showRsvpDialog"
      title="RSVP required"
      size="sm"
      @close="showRsvpDialog = false"
    >
      <p class="text-sm text-gray-600 dark:text-stone-400">
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
</template>
