<script setup lang="ts">
import { ref, computed } from 'vue'
import { useChoreRostersStore } from '@/stores/choreRosters'
import AnchoredPopover from '@/components/common/AnchoredPopover.vue'
import type {
  PoolMember,
  PoolRsvp,
  PoolChoreAssignment,
  PoolEvent,
} from '@/types/pool'
import { TEXT_LIMITS } from '@/constants/limits'
import { attendedDates } from '@/utils/event'

const props = defineProps<{
  choreId: string
  date: string
  anchorEl: HTMLElement
  rosterId: string
  members: PoolMember[]
  rsvps: PoolRsvp[]
  assignments: PoolChoreAssignment[]
  event: PoolEvent
}>()

const emit = defineEmits<{
  close: []
}>()

const choreRostersStore = useChoreRostersStore()
const note = ref('')

// Users available on this date (attending RSVP covering this date)
const availableMembers = computed(() => {
  const eventStart = props.event.startDate
  const eventEnd = props.event.endDate
  const dateVal = props.date

  const attendingUserIds = new Set<string>()
  if (eventStart && eventEnd) {
    for (const rsvp of props.rsvps) {
      // Use the attendee's actual day set so come-and-go gap days aren't
      // offered — matches the backend autofill availability.
      if (attendedDates(rsvp, eventStart, eventEnd).includes(dateVal)) {
        attendingUserIds.add(rsvp.userId)
      }
    }
  }

  // Filter out already assigned to this chore on this date
  const alreadyAssigned = new Set(
    props.assignments
      .filter((a) => a.choreId === props.choreId && a.date === props.date)
      .map((a) => a.userId)
  )

  return props.members
    .filter(
      (m) => attendingUserIds.has(m.userId) && !alreadyAssigned.has(m.userId)
    )
    .sort((a, b) => {
      const nameA = a.name ?? a.email
      const nameB = b.name ?? b.email
      return nameA.localeCompare(nameB)
    })
})

function getMemberDisplayName(member: PoolMember): string {
  return member.name ?? member.email.split('@')[0] ?? member.email
}

async function handleSelect(userId: string) {
  await choreRostersStore.createAssignment(
    props.rosterId,
    props.choreId,
    userId,
    props.date,
    note.value.trim() || undefined
  )
  emit('close')
}
</script>

<template>
  <AnchoredPopover
    :anchor-el="anchorEl"
    aria-label="Assign member"
    @close="emit('close')"
  >
    <p class="text-ink-muted mb-2 text-xs font-medium">Assign member</p>

    <input
      v-model="note"
      type="text"
      placeholder="Note (optional)"
      aria-label="Note (optional)"
      :maxlength="TEXT_LIMITS.shortText"
      class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder focus:outline-focus mb-2 block w-full rounded-md px-2 py-1 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 sm:text-sm"
    />

    <div class="max-h-48 overflow-y-auto">
      <button
        v-for="member in availableMembers"
        :key="member.id"
        type="button"
        class="text-ink focus-visible:outline-focus hover:bg-surface-sunken flex w-full cursor-pointer items-center rounded-md px-2 py-1.5 text-left text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
        @click="handleSelect(member.userId)"
      >
        {{ getMemberDisplayName(member) }}
      </button>
      <p
        v-if="availableMembers.length === 0"
        class="text-ink-muted py-2 text-center text-xs"
      >
        No available members
      </p>
    </div>
  </AnchoredPopover>
</template>
