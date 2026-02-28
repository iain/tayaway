<script setup lang="ts">
import { computed, ref, watchEffect } from 'vue'
import { useDraggable } from 'vue-draggable-plus'
import type { SortableEvent } from 'vue-draggable-plus'
import { Bars3Icon, TrashIcon } from '@heroicons/vue/24/outline'
import IconButton from '@/components/common/IconButton.vue'
import ChoreCell from '@/components/chores/ChoreCell.vue'
import { positionBetween } from '@/utils/position'
import { useChoreRostersStore } from '@/stores/choreRosters'
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

const choreRostersStore = useChoreRostersStore()

const memberMap = computed(() => {
  const map = new Map<string, PoolMember>()
  for (const m of props.members) {
    map.set(m.userId, m)
  }
  return map
})

// Local sorted list for drag-and-drop (synced from props)
const choresSorted = ref<PoolChore[]>([])

watchEffect(() => {
  choresSorted.value = [...props.chores]
})

const headerRow = ref<HTMLElement | null>(null)

useDraggable(headerRow, choresSorted, {
  draggable: '.chore-col',
  handle: '.chore-drag-handle',
  animation: 150,
  ghostClass: 'opacity-50',
  onEnd(event: SortableEvent) {
    const { oldIndex, newIndex } = event
    if (
      oldIndex === undefined ||
      newIndex === undefined ||
      oldIndex === newIndex
    )
      return

    const list = choresSorted.value
    const movedChore = list[newIndex]
    if (!movedChore) return

    const before = newIndex > 0 ? (list[newIndex - 1]?.position ?? null) : null
    const after =
      newIndex < list.length - 1 ? (list[newIndex + 1]?.position ?? null) : null

    choreRostersStore.updateChore(props.rosterId, movedChore.id, {
      position: positionBetween(before, after),
    })
  },
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
        <tr ref="headerRow" class="bg-gray-50 dark:bg-stone-800">
          <th
            class="sticky left-0 z-10 bg-gray-50 px-3 py-2 text-left text-xs font-medium tracking-wider text-gray-500 uppercase dark:bg-stone-800 dark:text-stone-400"
          >
            Date
          </th>
          <th
            v-for="chore in choresSorted"
            :key="chore.id"
            class="chore-col px-3 py-2 text-center text-xs font-medium tracking-wider whitespace-nowrap text-gray-500 uppercase dark:text-stone-400"
          >
            <div class="group inline-flex items-center gap-1">
              <Bars3Icon
                class="chore-drag-handle size-3.5 shrink-0 cursor-grab text-gray-300 opacity-0 transition-opacity group-hover:opacity-100 active:cursor-grabbing dark:text-stone-600"
              />
              <span>{{ chore.name }}</span>
              <IconButton
                hover-reveal
                label="Delete chore"
                class="shrink-0"
                @click="emit('deleteChore', chore.id)"
              >
                <TrashIcon class="size-3.5" />
              </IconButton>
            </div>
            <div
              v-if="chore.peoplePerDay > 1"
              class="text-[10px] font-normal tracking-normal text-gray-400 normal-case dark:text-stone-500"
            >
              {{ chore.peoplePerDay }}/day
            </div>
          </th>
        </tr>
      </thead>
      <tbody
        class="divide-y divide-gray-200 bg-white dark:divide-stone-700 dark:bg-stone-900"
      >
        <tr v-for="date in dates" :key="date">
          <td
            class="sticky left-0 z-10 bg-white px-3 py-2 text-sm font-medium whitespace-nowrap text-gray-900 dark:bg-stone-900 dark:text-white"
          >
            {{ formatDayHeader(date) }}
          </td>
          <td
            v-for="chore in choresSorted"
            :key="chore.id"
            class="px-1 py-1 text-center"
          >
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
