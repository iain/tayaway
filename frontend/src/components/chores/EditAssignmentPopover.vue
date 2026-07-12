<script setup lang="ts">
import { computed, ref } from 'vue'
import { useChoreRostersStore } from '@/stores/choreRosters'
import PushPinIcon from '@/components/icons/PushPinIcon.vue'
import AnchoredPopover from '@/components/common/AnchoredPopover.vue'
import type {
  PoolChoreAssignment,
  PoolEvent,
  PoolMember,
  PoolRsvp,
} from '@/types/pool'
import { getMemberNameFromMap } from '@/utils/member'
import { attendingUserIdsOn } from '@/utils/chores'
import { TEXT_LIMITS } from '@/constants/limits'
import TextButton from '@/components/common/TextButton.vue'
import AppButton from '@/components/common/AppButton.vue'

const props = defineProps<{
  assignment: PoolChoreAssignment
  anchorEl: HTMLElement
  rosterId: string
  memberMap: Map<string, PoolMember>
  assignments: PoolChoreAssignment[]
  rsvps: PoolRsvp[]
  event: PoolEvent
}>()

const emit = defineEmits<{
  close: []
}>()

const choreRostersStore = useChoreRostersStore()
const note = ref(props.assignment.note ?? '')
const showReassign = ref(false)

// Who could take this slot over: attending that day, not the current holder,
// not already on this same chore-day. Reassigning (rather than remove +
// re-add) keeps the note and pin intact.
const reassignCandidates = computed(() => {
  const attending = attendingUserIdsOn(
    props.assignment.date,
    props.rsvps,
    props.event
  )
  const slotMates = new Set(
    props.assignments
      .filter(
        (a) =>
          a.choreId === props.assignment.choreId &&
          a.date === props.assignment.date
      )
      .map((a) => a.userId)
  )

  return [...props.memberMap.values()]
    .filter((m) => attending.has(m.userId) && !slotMates.has(m.userId))
    .sort((a, b) => (a.name ?? a.email).localeCompare(b.name ?? b.email))
})

async function handleReassign(userId: string) {
  await choreRostersStore.updateAssignment(
    props.rosterId,
    props.assignment.id,
    { userId }
  )
  emit('close')
}

async function handleSaveNote() {
  const trimmed = note.value.trim()
  if (trimmed === (props.assignment.note ?? '')) {
    emit('close')
    return
  }
  await choreRostersStore.updateAssignment(
    props.rosterId,
    props.assignment.id,
    {
      note: trimmed || undefined,
    }
  )
  emit('close')
}

async function handleTogglePin() {
  await choreRostersStore.updateAssignment(
    props.rosterId,
    props.assignment.id,
    { pinned: !props.assignment.pinned }
  )
  emit('close')
}

async function handleRemove() {
  await choreRostersStore.deleteAssignment(props.rosterId, props.assignment.id)
  emit('close')
}
</script>

<template>
  <AnchoredPopover
    :anchor-el="anchorEl"
    :aria-label="`Edit ${getMemberNameFromMap(assignment.userId, memberMap)}'s assignment`"
    @close="emit('close')"
  >
    <div class="mb-2 flex items-center justify-between">
      <p class="text-ink-muted text-xs font-medium">
        {{ getMemberNameFromMap(assignment.userId, memberMap) }}
      </p>
      <button
        type="button"
        class="focus-visible:outline-focus cursor-pointer rounded p-1 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
        :class="
          assignment.pinned
            ? 'text-state-warning-ink hover:bg-state-warning-fill'
            : 'text-ink-muted hover:bg-surface-sunken hover:text-ink'
        "
        :title="assignment.pinned ? 'Unpin' : 'Pin'"
        @click="handleTogglePin"
      >
        <PushPinIcon class="size-3.5" />
      </button>
    </div>

    <input
      v-model="note"
      type="text"
      placeholder="Note (optional)"
      aria-label="Note (optional)"
      :maxlength="TEXT_LIMITS.shortText"
      class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder focus:outline-focus mb-3 block w-full rounded-md px-2 py-1 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 sm:text-sm"
      @keydown.enter="handleSaveNote"
    />

    <button
      type="button"
      aria-label="Reassign"
      :aria-expanded="showReassign"
      class="text-ink-muted focus-visible:outline-focus hover:text-ink mb-3 block w-full cursor-pointer rounded text-left text-sm focus-visible:outline-2 focus-visible:outline-offset-2"
      @click="showReassign = !showReassign"
    >
      Reassign to…
    </button>

    <div v-if="showReassign" class="mb-3 max-h-40 overflow-y-auto">
      <button
        v-for="member in reassignCandidates"
        :key="member.id"
        type="button"
        :aria-label="`Reassign to ${getMemberNameFromMap(member.userId, memberMap)}`"
        class="text-ink focus-visible:outline-focus hover:bg-surface-sunken block w-full cursor-pointer rounded-md px-2 py-1.5 text-left text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
        @click="handleReassign(member.userId)"
      >
        {{ getMemberNameFromMap(member.userId, memberMap) }}
      </button>
      <p
        v-if="reassignCandidates.length === 0"
        class="text-ink-muted py-2 text-center text-xs"
      >
        No one else is around that day
      </p>
    </div>

    <div class="flex items-center justify-between">
      <TextButton variant="danger" @click="handleRemove"> Remove </TextButton>
      <AppButton size="sm" @click="handleSaveNote"> Save </AppButton>
    </div>
  </AnchoredPopover>
</template>
