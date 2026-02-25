<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  TrashIcon,
  ChevronDownIcon,
  PencilIcon,
  LockClosedIcon,
} from '@heroicons/vue/24/outline'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useExpensesStore } from '@/stores/expenses'
import { countDays } from '@/utils/event'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import type { PoolExpense, PoolEvent } from '@/types/pool'

const props = defineProps<{
  expense: PoolExpense
  event: PoolEvent
  currentUserId: string | null
  stripe?: boolean
}>()

const pool = useObjectPoolStore()
const expensesStore = useExpensesStore()

const emit = defineEmits<{
  edit: [expense: PoolExpense]
}>()

const expanded = ref(false)

const member = computed(() => {
  if (!props.expense.userId) return null
  return pool.findBy('member', 'userId', props.expense.userId)
})

const displayName = computed(() => {
  return member.value?.name || member.value?.email || 'Unknown'
})

const formattedAmount = computed(() => {
  return `€${props.expense.amount.toFixed(2)}`
})

const isOwner = computed(() => {
  return props.expense.userId === props.currentUserId
})

const isSettled = computed(() => {
  return !!props.expense.settlementId
})

interface ExpensePayer {
  name: string
  overlapDays: number
  share: number
}

const payers = computed((): ExpensePayer[] => {
  const attendingRsvps = pool
    .getAll('rsvp')
    .filter((r) => r.eventId === props.event.id && r.attending)

  if (attendingRsvps.length === 0) return []

  const withOverlap = attendingRsvps
    .map((rsvp) => {
      const rsvpStart = rsvp.startDate ?? props.event.startDate
      const rsvpEnd = rsvp.endDate ?? props.event.endDate
      if (!rsvpStart || !rsvpEnd) return null

      const overlapStart =
        props.expense.startDate > rsvpStart
          ? props.expense.startDate
          : rsvpStart
      const overlapEnd =
        props.expense.endDate < rsvpEnd ? props.expense.endDate : rsvpEnd

      if (overlapStart > overlapEnd) return null

      const overlapDays = countDays(overlapStart, overlapEnd)
      if (overlapDays <= 0) return null

      const m = pool.findBy('member', 'userId', rsvp.userId)
      return {
        name: m?.name ?? m?.email ?? 'Unknown',
        overlapDays,
      }
    })
    .filter((p): p is { name: string; overlapDays: number } => p !== null)

  const totalOverlapDays = withOverlap.reduce(
    (sum, p) => sum + p.overlapDays,
    0
  )
  if (totalOverlapDays === 0) return []

  return withOverlap.map((p) => ({
    ...p,
    share: (p.overlapDays / totalOverlapDays) * props.expense.amount,
  }))
})

function toggleExpand() {
  expanded.value = !expanded.value
}

function handleEdit(e: Event) {
  e.stopPropagation()
  emit('edit', props.expense)
}

async function handleDelete(e: Event) {
  e.stopPropagation()
  await expensesStore.deleteExpense(props.expense.id)
}
</script>

<template>
  <tr
    data-testid="expense-row"
    :class="[
      stripe ? 'bg-gray-50 dark:bg-black/20' : '',
      'cursor-pointer select-none',
    ]"
    @click="toggleExpand"
  >
    <td class="py-3 pr-4 pl-2 align-middle">
      <p class="truncate text-sm text-gray-900 dark:text-white">
        {{ expense.description }}
      </p>
      <p class="text-xs text-gray-500 dark:text-stone-400">
        {{ displayName }}
      </p>
      <p
        v-if="event.startDate && event.endDate"
        class="text-xs text-gray-400 dark:text-stone-500"
      >
        <DateRangeDisplay
          :start-date="expense.startDate"
          :end-date="expense.endDate"
        />
      </p>
    </td>
    <td
      class="py-3 pr-4 text-right align-middle font-mono text-sm font-medium whitespace-nowrap text-gray-900 dark:text-white"
    >
      {{ formattedAmount }}
    </td>
    <td class="w-12 py-3 pr-2 align-middle">
      <div class="flex items-center gap-1">
        <LockClosedIcon
          v-if="isSettled"
          class="size-4 text-gray-300 dark:text-stone-600"
          title="Part of a settlement"
        />
        <template v-else>
          <button
            v-if="isOwner"
            type="button"
            data-testid="edit-expense"
            class="flex text-gray-400 hover:text-blue-500 dark:text-stone-500 dark:hover:text-blue-400"
            @click="handleEdit"
          >
            <PencilIcon class="size-4" />
          </button>
          <button
            v-if="isOwner"
            type="button"
            data-testid="delete-expense"
            class="flex text-gray-400 hover:text-red-500 dark:text-stone-500 dark:hover:text-red-400"
            @click="handleDelete"
          >
            <TrashIcon class="size-4" />
          </button>
        </template>
        <ChevronDownIcon
          class="size-4 text-gray-400 transition-transform dark:text-stone-500"
          :class="{ 'rotate-180': expanded }"
        />
      </div>
    </td>
  </tr>
  <tr v-if="expanded" data-testid="expense-detail">
    <td
      colspan="3"
      class="px-2 pb-3"
      :class="stripe ? 'bg-gray-50 dark:bg-black/20' : ''"
    >
      <div
        class="rounded-md border border-gray-200 bg-white p-3 dark:border-stone-600 dark:bg-stone-800"
      >
        <p
          v-if="payers.length === 0"
          class="text-xs text-gray-500 dark:text-stone-400"
        >
          No overlapping attendees for this expense.
        </p>
        <table v-else class="w-full text-xs">
          <thead>
            <tr class="text-left text-gray-500 uppercase dark:text-stone-400">
              <th class="pr-2 pb-1">Person</th>
              <th class="pr-2 pb-1">Days</th>
              <th class="pb-1 text-right">Share</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="payer in payers"
              :key="payer.name"
              class="text-gray-700 dark:text-stone-300"
            >
              <td class="py-0.5 pr-2">{{ payer.name }}</td>
              <td class="py-0.5 pr-2">{{ payer.overlapDays }}</td>
              <td class="py-0.5 text-right font-mono">
                €{{ payer.share.toFixed(2) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </td>
  </tr>
</template>
