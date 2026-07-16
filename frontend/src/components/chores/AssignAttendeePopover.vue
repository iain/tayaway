<script setup lang="ts">
import { computed } from 'vue'
import { CheckIcon } from '@heroicons/vue/20/solid'
import { useChoreRostersStore } from '@/stores/choreRosters'
import AnchoredPopover from '@/components/common/AnchoredPopover.vue'
import type { PoolChore, PoolChoreAssignment, PoolEvent } from '@/types/pool'
import type { HydratedAttendance } from '@/composables/useHydratedEvent'
import { assignableAttendancesOn, holderAttendanceId } from '@/utils/chores'
import { formatDayHeader } from '@/utils/date'

const props = defineProps<{
  chore: PoolChore
  date: string
  anchorEl: HTMLElement
  rosterId: string
  attendances: HydratedAttendance[]
  assignments: PoolChoreAssignment[]
  event: PoolEvent
  currentUserId: string | null
}>()

const emit = defineEmits<{
  close: []
}>()

const choreRostersStore = useChoreRostersStore()

// Attendances covering this date (so come-and-go gap days aren't offered —
// matches the backend autofill availability). The viewer sorts first
// (claiming a slot yourself is the most common assignment by far), then
// members, then guests — the same ordering as the day view.
const candidates = computed(() => {
  return assignableAttendancesOn(props.date, props.attendances, props.event)
    .slice()
    .sort((a, b) => {
      if (isCurrentUser(a)) return -1
      if (isCurrentUser(b)) return 1
      return (
        Number(a.attendee.isGuest) - Number(b.attendee.isGuest) ||
        a.attendee.name.localeCompare(b.attendee.name)
      )
    })
})

function isCurrentUser(attendance: HydratedAttendance): boolean {
  return (
    props.currentUserId !== null &&
    attendance.attendee.member?.userId === props.currentUserId
  )
}

function displayName(attendance: HydratedAttendance): string {
  if (isCurrentUser(attendance)) return 'You'
  if (attendance.attendee.isGuest) return `${attendance.attendee.name} (guest)`
  return attendance.attendee.name
}

// This slot's assignments keyed by attendance, so a row can flip between
// "assign" and "remove" and show its check. Legacy rows without the link
// resolve through their mirrored userId.
const slotAssignments = computed(() => {
  const byUser = new Map<string, string>()
  for (const a of props.attendances) {
    if (a.userId) byUser.set(a.userId, a.id)
  }
  const map = new Map<string, PoolChoreAssignment>()
  for (const a of props.assignments) {
    if (a.choreId === props.chore.id && a.date === props.date) {
      const attendanceId = holderAttendanceId(a, byUser)
      if (attendanceId) map.set(attendanceId, a)
    }
  }
  return map
})

const spotsLeft = computed(
  () => props.chore.peoplePerDay - slotAssignments.value.size
)

async function handleToggle(attendance: HydratedAttendance) {
  const existing = slotAssignments.value.get(attendance.id)
  if (existing) {
    await choreRostersStore.deleteAssignment(props.rosterId, existing.id)
  } else if (spotsLeft.value > 0) {
    const wasLastSpot = spotsLeft.value === 1
    await choreRostersStore.createAssignment(
      props.rosterId,
      props.chore.id,
      {
        attendanceId: attendance.id,
        userId: attendance.attendee.member?.userId ?? null,
      },
      props.date
    )
    if (wasLastSpot) {
      emit('close')
    }
  }
}
</script>

<template>
  <AnchoredPopover
    :anchor-el="anchorEl"
    aria-label="Assign someone"
    @close="emit('close')"
  >
    <div class="mb-2">
      <p class="text-ink text-sm font-medium">{{ chore.name }}</p>
      <p class="text-ink-muted text-xs">
        {{ formatDayHeader(date)
        }}<template v-if="chore.peoplePerDay > 1">
          · {{ spotsLeft }}
          {{ spotsLeft === 1 ? 'spot' : 'spots' }} left</template
        >
      </p>
    </div>

    <div class="max-h-56 overflow-y-auto">
      <button
        v-for="attendance in candidates"
        :key="attendance.id"
        type="button"
        class="text-ink focus-visible:outline-focus hover:bg-surface-sunken flex w-full cursor-pointer items-center justify-between gap-2 rounded-md px-2 py-1.5 text-left text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
        :aria-label="`${slotAssignments.has(attendance.id) ? 'Remove' : 'Assign'} ${displayName(attendance)}`"
        @click="handleToggle(attendance)"
      >
        <span
          class="truncate"
          :class="isCurrentUser(attendance) ? 'font-medium' : ''"
        >
          {{ displayName(attendance) }}
        </span>
        <CheckIcon
          v-if="slotAssignments.has(attendance.id)"
          class="text-state-success-ink size-4 shrink-0"
          aria-hidden="true"
        />
      </button>
      <p
        v-if="candidates.length === 0"
        class="text-ink-muted py-2 text-center text-xs"
      >
        No one is attending this day
      </p>
    </div>
  </AnchoredPopover>
</template>
