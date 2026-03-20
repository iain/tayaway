<script setup lang="ts">
import { computed } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { countDays } from '@/utils/event'
import type { PoolEvent, PoolMember } from '@/types/pool'

const props = defineProps<{
  event: PoolEvent
  startDate: string
  endDate: string
  everyone: boolean
}>()

const emit = defineEmits<{
  'update:everyone': [value: boolean]
}>()

const selectedUserIds = defineModel<string[]>('selectedUserIds', {
  required: true,
})

const pool = useObjectPoolStore()

interface SelectableMember {
  member: PoolMember
  userId: string
  name: string
}

const overlappingMembers = computed((): SelectableMember[] => {
  if (!props.startDate || !props.endDate) return []

  const attendingRsvps = pool
    .getAll('rsvp')
    .filter((r) => r.eventId === props.event.id && r.attending)

  return attendingRsvps
    .map((rsvp) => {
      const rsvpStart = rsvp.startDate ?? props.event.startDate
      const rsvpEnd = rsvp.endDate ?? props.event.endDate
      if (!rsvpStart || !rsvpEnd) return null

      const overlapStart =
        props.startDate > rsvpStart ? props.startDate : rsvpStart
      const overlapEnd = props.endDate < rsvpEnd ? props.endDate : rsvpEnd

      if (overlapStart > overlapEnd) return null
      if (countDays(overlapStart, overlapEnd) <= 0) return null

      const member = pool.findBy('member', 'userId', rsvp.userId)
      if (!member) return null

      return {
        member,
        userId: rsvp.userId,
        name: member.name ?? member.email,
      }
    })
    .filter((m): m is SelectableMember => m !== null)
    .sort((a, b) => a.name.localeCompare(b.name))
})

function toggleEveryone(): void {
  emit('update:everyone', !props.everyone)
  if (!props.everyone) {
    selectedUserIds.value = []
  }
}

function toggleUser(userId: string): void {
  const current = selectedUserIds.value
  if (current.includes(userId)) {
    selectedUserIds.value = current.filter((id) => id !== userId)
  } else {
    selectedUserIds.value = [...current, userId]
  }
}
</script>

<template>
  <div>
    <div class="mb-3 flex items-center justify-between">
      <p class="text-sm font-medium text-gray-700 dark:text-stone-300">
        Who is this for?
      </p>
      <button
        type="button"
        class="min-h-[44px] px-1 text-xs font-medium text-cyan-600 hover:text-cyan-700 sm:min-h-0 dark:text-cyan-400 dark:hover:text-cyan-300"
        data-testid="toggle-people-mode"
        @click="toggleEveryone"
      >
        {{ everyone ? 'Specific people' : 'Everyone' }}
      </button>
    </div>

    <div v-if="everyone" class="text-sm text-gray-500 dark:text-stone-400">
      Split by attendance overlap — everyone who RSVPs will be included
      automatically.
    </div>

    <div v-else>
      <p
        v-if="overlappingMembers.length === 0"
        class="text-sm text-gray-500 dark:text-stone-400"
      >
        No attending members overlap with this expense period. Go back and
        adjust the dates, or switch to Everyone.
      </p>
      <div v-else>
        <div class="space-y-1">
          <label
            v-for="m in overlappingMembers"
            :key="m.userId"
            class="flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2 transition-colors focus-within:bg-gray-100 hover:bg-gray-100 dark:focus-within:bg-white/5 dark:hover:bg-white/5"
            :data-testid="`participant-${m.userId}`"
          >
            <input
              type="checkbox"
              class="size-4 rounded border-gray-300 text-rose-500 focus:ring-rose-500 dark:border-stone-600 dark:bg-stone-800"
              :checked="selectedUserIds.includes(m.userId)"
              @change="toggleUser(m.userId)"
            />
            <span class="text-sm text-gray-900 dark:text-white">
              {{ m.name }}
            </span>
          </label>
        </div>
        <p class="mt-2 text-xs text-gray-500 dark:text-stone-400">
          {{ selectedUserIds.length }} of
          {{ overlappingMembers.length }} selected
        </p>
      </div>
    </div>
  </div>
</template>
