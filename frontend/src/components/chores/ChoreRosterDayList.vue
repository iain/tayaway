<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import ChoreCell from '@/components/chores/ChoreCell.vue'
import type { PoolChore, PoolChoreAssignment, PoolMember } from '@/types/pool'

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
}>()

const emit = defineEmits<{
  assign: [choreId: string, date: string, anchorEl: HTMLElement]
  editAssignment: [assignment: PoolChoreAssignment, anchorEl: HTMLElement]
}>()

const pad = (n: number) => String(n).padStart(2, '0')

// Local calendar date, formatted to match the ISO day strings the event
// produces, so "today" lines up in the user's own timezone.
const todayIso = (() => {
  const n = new Date()
  return `${n.getFullYear()}-${pad(n.getMonth() + 1)}-${pad(n.getDate())}`
})()

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
  return date === todayIso
}

function formatDayHeader(date: string): string {
  const d = new Date(date + 'T12:00:00')
  return d.toLocaleDateString(undefined, {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  })
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
    `[data-date="${todayIso}"]`
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
    <section
      v-for="date in dates"
      :key="date"
      :data-date="date"
      class="scroll-mt-20"
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
            @assign="(el: HTMLElement) => emit('assign', chore.id, date, el)"
            @edit-assignment="(a, el) => emit('editAssignment', a, el)"
          />
        </div>
      </div>
    </section>
  </div>
</template>
