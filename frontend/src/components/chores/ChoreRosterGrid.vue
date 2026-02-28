<script setup lang="ts">
import { computed } from 'vue'
import { TrashIcon } from '@heroicons/vue/24/outline'
import IconButton from '@/components/common/IconButton.vue'
import ChoreCell from '@/components/chores/ChoreCell.vue'
import type {
  PoolChore,
  PoolChoreAssignment,
  PoolMember,
  PoolRsvp,
} from '@/types/pool'

const props = defineProps<{
  chores: PoolChore[]
  assignments: PoolChoreAssignment[]
  dates: string[]
  members: PoolMember[]
  rsvps: PoolRsvp[]
  rosterId: string
  currentUserId: string | null
}>()

const emit = defineEmits<{
  assign: [choreId: string, date: string, anchorEl: HTMLElement]
  editAssignment: [assignment: PoolChoreAssignment, anchorEl: HTMLElement]
  deleteChore: [choreId: string]
}>()

const memberMap = computed(() => {
  const map = new Map<string, PoolMember>()
  for (const m of props.members) {
    map.set(m.userId, m)
  }
  return map
})

// Build a lookup: choreId-date -> assignment[]
const assignmentMap = computed(() => {
  const map = new Map<string, PoolChoreAssignment[]>()
  for (const a of props.assignments) {
    const key = `${a.choreId}-${a.date}`
    const list = map.get(key)
    if (list) {
      list.push(a)
    } else {
      map.set(key, [a])
    }
  }
  return map
})

function formatDayHeader(dateStr: string): string {
  const d = new Date(dateStr + 'T12:00:00')
  const day = d.toLocaleDateString(undefined, { weekday: 'short' })
  const num = d.getDate()
  return `${day} ${num}`
}

function getAssignments(choreId: string, date: string): PoolChoreAssignment[] {
  return assignmentMap.value.get(`${choreId}-${date}`) ?? []
}
</script>

<template>
  <div
    class="overflow-x-auto rounded-lg border border-gray-200 dark:border-stone-700"
  >
    <table class="min-w-full divide-y divide-gray-200 dark:divide-stone-700">
      <thead>
        <tr class="bg-gray-50 dark:bg-stone-800">
          <th
            class="sticky left-0 z-10 bg-gray-50 px-3 py-2 text-left text-xs font-medium tracking-wider text-gray-500 uppercase dark:bg-stone-800 dark:text-stone-400"
          >
            Chore
          </th>
          <th
            v-for="date in dates"
            :key="date"
            class="px-3 py-2 text-center text-xs font-medium tracking-wider whitespace-nowrap text-gray-500 uppercase dark:text-stone-400"
          >
            {{ formatDayHeader(date) }}
          </th>
        </tr>
      </thead>
      <tbody
        class="divide-y divide-gray-200 bg-white dark:divide-stone-700 dark:bg-stone-900"
      >
        <tr v-for="chore in chores" :key="chore.id">
          <td class="sticky left-0 z-10 bg-white px-3 py-2 dark:bg-stone-900">
            <div class="group flex items-center gap-1">
              <div class="min-w-0">
                <div class="text-sm font-medium text-gray-900 dark:text-white">
                  {{ chore.name }}
                </div>
                <div
                  v-if="chore.peoplePerDay > 1"
                  class="text-xs text-gray-500 dark:text-stone-400"
                >
                  {{ chore.peoplePerDay }} people/day
                </div>
              </div>
              <IconButton
                hover-reveal
                label="Delete chore"
                class="shrink-0"
                @click="emit('deleteChore', chore.id)"
              >
                <TrashIcon class="size-4" />
              </IconButton>
            </div>
          </td>
          <td v-for="date in dates" :key="date" class="px-1 py-1 text-center">
            <ChoreCell
              :assignments="getAssignments(chore.id, date)"
              :people-per-day="chore.peoplePerDay"
              :member-map="memberMap"
              @assign="(el: HTMLElement) => emit('assign', chore.id, date, el)"
              @edit-assignment="(a, el) => emit('editAssignment', a, el)"
            />
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
