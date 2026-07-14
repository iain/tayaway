<script setup lang="ts">
import { computed, ref, watchEffect } from 'vue'
import { useDraggable } from 'vue-draggable-plus'
import type { SortableEvent } from 'vue-draggable-plus'
import { Bars3Icon, ClockIcon, TrashIcon } from '@heroicons/vue/24/outline'
import IconButton from '@/components/common/IconButton.vue'
import ChoreCell from '@/components/chores/ChoreCell.vue'
import { positionBetween, positionForReorder } from '@/utils/position'
import { useChoreRostersStore } from '@/stores/choreRosters'
import type {
  PoolChore,
  PoolChoreAssignment,
  PoolMember,
  PoolAttendance,
} from '@/types/pool'

const props = defineProps<{
  chores: PoolChore[]
  assignments: PoolChoreAssignment[]
  dates: string[]
  members: PoolMember[]
  attendances: PoolAttendance[]
  rosterId: string
  currentUserId: string | null
  // The event-zone date — the same "today" the backend fences autofill on,
  // so the muted past matches exactly what a re-fill would leave alone.
  today: string
  staleAssignmentIds?: Set<string>
}>()

const emit = defineEmits<{
  assign: [choreId: string, date: string, anchorEl: HTMLElement]
  editAssignment: [assignment: PoolChoreAssignment, anchorEl: HTMLElement]
  editChoreTime: [chore: PoolChore, anchorEl: HTMLElement]
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
    const { oldDraggableIndex, newDraggableIndex } = event
    if (
      oldDraggableIndex === undefined ||
      newDraggableIndex === undefined ||
      oldDraggableIndex === newDraggableIndex
    )
      return

    const list = choresSorted.value
    const movedChore = list[newDraggableIndex]
    if (!movedChore) return

    const before =
      newDraggableIndex > 0
        ? (list[newDraggableIndex - 1]?.position ?? null)
        : null
    const after =
      newDraggableIndex < list.length - 1
        ? (list[newDraggableIndex + 1]?.position ?? null)
        : null

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

// Politely announce keyboard reorders; drag has its own visual feedback, but a
// keyboard user moving a column off-screen needs spoken confirmation.
const reorderAnnouncement = ref('')

// Keyboard-accessible counterpart to the mouse drag: arrow keys on a column's
// handle hop it past the neighbour in that direction, using the same
// position-between math the drag's onEnd uses.
function moveChore(chore: PoolChore, direction: 'left' | 'right') {
  const list = choresSorted.value
  const i = list.findIndex((c) => c.id === chore.id)
  if (i === -1) return
  const target = direction === 'left' ? i - 1 : i + 1
  if (target < 0 || target >= list.length) return

  choreRostersStore.updateChore(props.rosterId, chore.id, {
    position: positionForReorder(
      list.map((c) => c.position),
      i,
      direction === 'left' ? 'up' : 'down'
    ),
  })
  reorderAnnouncement.value = `${chore.name} moved to position ${target + 1} of ${list.length}`
}

function onHandleKeydown(event: KeyboardEvent, chore: PoolChore) {
  if (event.key === 'ArrowLeft') {
    event.preventDefault()
    moveChore(chore, 'left')
  } else if (event.key === 'ArrowRight') {
    event.preventDefault()
    moveChore(chore, 'right')
  }
}
</script>

<template>
  <div class="border-line overflow-x-auto rounded-lg border">
    <div role="status" aria-live="polite" class="sr-only">
      {{ reorderAnnouncement }}
    </div>
    <table class="divide-line min-w-full divide-y">
      <caption class="sr-only">
        Chore roster: who is assigned to each chore on each day. Use the reorder
        handle in a column header with the left and right arrow keys to move a
        chore.
      </caption>
      <thead>
        <tr ref="headerRow" class="bg-surface-sunken">
          <th
            scope="col"
            class="bg-surface-sunken text-ink-muted sticky left-0 z-10 px-3 py-2 text-left text-xs font-medium tracking-wider uppercase"
          >
            Date
          </th>
          <th
            v-for="chore in choresSorted"
            :key="chore.id"
            scope="col"
            class="chore-col text-ink-muted px-3 py-2 text-center text-xs font-medium tracking-wider whitespace-nowrap uppercase"
          >
            <div class="group inline-flex items-center gap-1">
              <IconButton
                hover-reveal
                class="chore-drag-handle shrink-0 cursor-grab active:cursor-grabbing"
                label="Reorder chore"
                aria-keyshortcuts="ArrowLeft ArrowRight"
                @keydown="(e: KeyboardEvent) => onHandleKeydown(e, chore)"
              >
                <Bars3Icon class="size-3.5" />
              </IconButton>
              <span>{{ chore.name }}</span>
              <IconButton
                hover-reveal
                label="Edit reminder time"
                class="shrink-0"
                @click="
                  (e: MouseEvent) =>
                    emit('editChoreTime', chore, e.currentTarget as HTMLElement)
                "
              >
                <ClockIcon class="size-3.5" />
              </IconButton>
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
              class="text-ink-muted text-xs font-normal tracking-normal normal-case"
            >
              {{ chore.peoplePerDay }}/day
            </div>
            <div
              v-if="chore.time"
              class="text-ink-muted text-xs font-normal tracking-normal normal-case"
            >
              at {{ chore.time }}
            </div>
          </th>
        </tr>
      </thead>
      <tbody class="divide-line bg-surface divide-y">
        <!-- Past rows stay as the record of who did what, muted so the live
             part of the roster reads apart from history. -->
        <tr
          v-for="date in dates"
          :key="date"
          :class="date < today ? 'opacity-60' : ''"
        >
          <th
            scope="row"
            class="text-ink bg-surface-page sticky left-0 z-10 px-3 py-2 text-left text-sm whitespace-nowrap"
            :class="date === today ? 'font-semibold' : 'font-medium'"
          >
            {{ formatDayHeader(date) }}
            <span
              v-if="date === today"
              class="bg-ink text-surface ml-1 rounded-full px-1.5 py-0.5 text-[10px] font-medium"
            >
              Today
            </span>
          </th>
          <td
            v-for="chore in choresSorted"
            :key="chore.id"
            class="px-1 py-1 text-center"
          >
            <ChoreCell
              :assignments="getAssignments(chore.id, date)"
              :people-per-day="chore.peoplePerDay"
              :member-map="memberMap"
              :current-user-id="currentUserId"
              :stale-assignment-ids="staleAssignmentIds"
              @assign="(el: HTMLElement) => emit('assign', chore.id, date, el)"
              @edit-assignment="(a, el) => emit('editAssignment', a, el)"
            />
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
