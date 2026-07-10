<script setup lang="ts">
import { computed } from 'vue'
import { CheckIcon } from '@heroicons/vue/20/solid'
import { useChoreRostersStore } from '@/stores/choreRosters'
import AnchoredPopover from '@/components/common/AnchoredPopover.vue'
import type {
  PoolChore,
  PoolMember,
  PoolRsvp,
  PoolChoreAssignment,
  PoolEvent,
} from '@/types/pool'
import { attendedDates } from '@/utils/event'
import { formatDayHeader } from '@/utils/date'

const props = defineProps<{
  chore: PoolChore
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

// Members attending on this date (attending RSVP covering this date)
const attendingMembers = computed(() => {
  const eventStart = props.event.startDate
  const eventEnd = props.event.endDate

  const attendingUserIds = new Set<string>()
  if (eventStart && eventEnd) {
    for (const rsvp of props.rsvps) {
      // Use the attendee's actual day set so come-and-go gap days aren't
      // offered — matches the backend autofill availability.
      if (attendedDates(rsvp, eventStart, eventEnd).includes(props.date)) {
        attendingUserIds.add(rsvp.userId)
      }
    }
  }

  return props.members
    .filter((m) => attendingUserIds.has(m.userId))
    .sort((a, b) => {
      const nameA = a.name ?? a.email
      const nameB = b.name ?? b.email
      return nameA.localeCompare(nameB)
    })
})

function getMemberDisplayName(member: PoolMember): string {
  return member.name ?? member.email.split('@')[0] ?? member.email
}

// This slot's assignments keyed by user, so a member row can flip between
// "assign" and "remove" and show its check.
const slotAssignments = computed(() => {
  const map = new Map<string, PoolChoreAssignment>()
  for (const a of props.assignments) {
    if (a.choreId === props.chore.id && a.date === props.date) {
      map.set(a.userId, a)
    }
  }
  return map
})

const spotsLeft = computed(
  () => props.chore.peoplePerDay - slotAssignments.value.size
)

async function handleToggle(userId: string) {
  const existing = slotAssignments.value.get(userId)
  if (existing) {
    await choreRostersStore.deleteAssignment(props.rosterId, existing.id)
  } else if (spotsLeft.value > 0) {
    const wasLastSpot = spotsLeft.value === 1
    await choreRostersStore.createAssignment(
      props.rosterId,
      props.chore.id,
      userId,
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
    aria-label="Assign member"
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
        v-for="member in attendingMembers"
        :key="member.id"
        type="button"
        class="text-ink focus-visible:outline-focus hover:bg-surface-sunken flex w-full cursor-pointer items-center justify-between gap-2 rounded-md px-2 py-1.5 text-left text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
        :aria-label="`${slotAssignments.has(member.userId) ? 'Remove' : 'Assign'} ${getMemberDisplayName(member)}`"
        @click="handleToggle(member.userId)"
      >
        <span class="truncate">{{ getMemberDisplayName(member) }}</span>
        <CheckIcon
          v-if="slotAssignments.has(member.userId)"
          class="text-state-success-ink size-4 shrink-0"
          aria-hidden="true"
        />
      </button>
      <p
        v-if="attendingMembers.length === 0"
        class="text-ink-muted py-2 text-center text-xs"
      >
        No one is attending this day
      </p>
    </div>
  </AnchoredPopover>
</template>
