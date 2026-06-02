<script setup lang="ts">
import { ref, computed, onMounted, onBeforeUnmount } from 'vue'
import { useChoreRostersStore } from '@/stores/choreRosters'
import type {
  PoolMember,
  PoolRsvp,
  PoolChoreAssignment,
  PoolEvent,
} from '@/types/pool'

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
const popoverRef = ref<HTMLDivElement | null>(null)

// Users available on this date (attending RSVP covering this date)
const availableMembers = computed(() => {
  const eventStart = props.event.startDate
  const eventEnd = props.event.endDate
  const dateVal = props.date

  const attendingUserIds = new Set<string>()
  for (const rsvp of props.rsvps) {
    const rsvpStart = rsvp.startDate ?? eventStart
    const rsvpEnd = rsvp.endDate ?? eventEnd
    if (rsvpStart && rsvpEnd && dateVal >= rsvpStart && dateVal <= rsvpEnd) {
      attendingUserIds.add(rsvp.userId)
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

function handleClickOutside(event: MouseEvent) {
  if (popoverRef.value && !popoverRef.value.contains(event.target as Node)) {
    emit('close')
  }
}

onMounted(() => {
  document.addEventListener('mousedown', handleClickOutside)
})

onBeforeUnmount(() => {
  document.removeEventListener('mousedown', handleClickOutside)
})
</script>

<template>
  <div
    ref="popoverRef"
    class="border-line bg-surface fixed z-50 w-64 rounded-lg border p-3 shadow-lg"
    :style="{
      top: `${anchorEl.getBoundingClientRect().bottom + 4}px`,
      left: `${anchorEl.getBoundingClientRect().left}px`,
    }"
  >
    <p class="text-ink-muted mb-2 text-xs font-medium">Assign member</p>

    <input
      v-model="note"
      type="text"
      placeholder="Note (optional)"
      class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder focus:outline-focus mb-2 block w-full rounded-md px-2 py-1 text-sm outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2"
    />

    <div class="max-h-48 overflow-y-auto">
      <button
        v-for="member in availableMembers"
        :key="member.id"
        type="button"
        class="text-ink focus-visible:outline-focus flex w-full cursor-pointer items-center rounded-md px-2 py-1.5 text-left text-sm transition-colors hover:bg-gray-100 focus-visible:outline-2 focus-visible:outline-offset-2 dark:hover:bg-stone-700"
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
  </div>
</template>
