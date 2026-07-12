<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import ChoreCell from '@/components/chores/ChoreCell.vue'
import type { PoolChore, PoolChoreAssignment, PoolMember } from '@/types/pool'
import { formatDayHeader } from '@/utils/date'

// The mobile face of the chore roster. Where the desktop grid is a dates x
// chores matrix, this stacks the same data day by day: the "what's on today?"
// question a phone gets opened to answer mid-event. Today is emphasized and
// scrolled to on open. Chore-level settings (time, order, delete) don't live
// here because chores repeat under every day; they move to the manage sheet.
const props = defineProps<{
  chores: PoolChore[]
  assignments: PoolChoreAssignment[]
  dates: string[]
  members: PoolMember[]
  currentUserId: string | null
  // The event-zone date (see zonedDateString) — the same "today" the backend
  // fences autofill on, so the emphasized row, the muted past, and what a
  // re-fill would actually touch all agree, traveller or not.
  today: string
  staleAssignmentIds?: Set<string>
}>()

const emit = defineEmits<{
  assign: [choreId: string, date: string, anchorEl: HTMLElement]
  editAssignment: [assignment: PoolChoreAssignment, anchorEl: HTMLElement]
}>()

const sortedChores = computed(() =>
  [...props.chores].sort((a, b) => a.position - b.position)
)

const memberMap = computed(() => {
  const map = new Map<string, PoolMember>()
  for (const m of props.members) map.set(m.userId, m)
  return map
})

const assignmentMap = computed(() => {
  const map = new Map<string, PoolChoreAssignment[]>()
  for (const a of props.assignments) {
    const key = `${a.choreId}-${a.date}`
    const list = map.get(key)
    if (list) list.push(a)
    else map.set(key, [a])
  }
  return map
})

function assignmentsFor(choreId: string, date: string): PoolChoreAssignment[] {
  return assignmentMap.value.get(`${choreId}-${date}`) ?? []
}

function isToday(date: string): boolean {
  return date === props.today
}

function choreMeta(chore: PoolChore): string {
  const parts: string[] = []
  if (chore.time) parts.push(chore.time)
  if (chore.peoplePerDay > 1) parts.push(`${chore.peoplePerDay} people`)
  return parts.join(' · ')
}

const rootEl = ref<HTMLElement | null>(null)

// Land the user on today, the row they almost always came to check. Guarded so
// it degrades to a no-op under jsdom and honors reduced-motion.
onMounted(() => {
  const target = rootEl.value?.querySelector<HTMLElement>(
    `[data-date="${props.today}"]`
  )
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  target?.scrollIntoView?.({
    block: 'start',
    behavior: reduce ? 'auto' : 'smooth',
  })
})
</script>

<template>
  <div
    ref="rootEl"
    class="border-line bg-surface divide-line-faint divide-y overflow-hidden rounded-lg border"
  >
    <!-- Past days stay on screen as the record of who did what, but muted so
         the live part of the roster reads apart from history. -->
    <section
      v-for="date in dates"
      :key="date"
      :data-date="date"
      class="scroll-mt-20"
      :class="date < today ? 'opacity-60' : ''"
    >
      <header
        class="bg-surface-sunken flex items-center justify-between gap-2 px-4 py-2"
      >
        <h3
          class="text-label"
          :class="isToday(date) ? 'text-ink font-semibold' : 'text-ink-muted'"
        >
          {{ formatDayHeader(date) }}
        </h3>
        <span
          v-if="isToday(date)"
          class="bg-ink text-surface rounded-full px-2 py-0.5 text-xs font-medium"
        >
          Today
        </span>
      </header>

      <div class="divide-line-faint divide-y">
        <div
          v-for="chore in sortedChores"
          :key="chore.id"
          :data-chore-id="chore.id"
          class="px-4 py-3"
        >
          <div class="mb-1.5 flex items-baseline justify-between gap-3">
            <span class="text-ink text-body font-medium">{{ chore.name }}</span>
            <span
              v-if="choreMeta(chore)"
              class="text-ink-muted text-meta shrink-0"
            >
              {{ choreMeta(chore) }}
            </span>
          </div>
          <ChoreCell
            orientation="row"
            :assignments="assignmentsFor(chore.id, date)"
            :people-per-day="chore.peoplePerDay"
            :member-map="memberMap"
            :current-user-id="currentUserId"
            :stale-assignment-ids="staleAssignmentIds"
            @assign="(el: HTMLElement) => emit('assign', chore.id, date, el)"
            @edit-assignment="(a, el) => emit('editAssignment', a, el)"
          />
        </div>
      </div>
    </section>
  </div>
</template>
