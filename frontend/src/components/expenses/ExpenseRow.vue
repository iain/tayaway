<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  TrashIcon,
  ChevronDownIcon,
  PencilIcon,
  LockClosedIcon,
} from '@heroicons/vue/24/outline'
import IconButton from '@/components/common/IconButton.vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useExpensesStore } from '@/stores/expenses'
import { countDays } from '@/utils/event'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import type { PoolExpense, PoolEvent } from '@/types/pool'
import BaseCard from '@/components/common/BaseCard.vue'

const props = defineProps<{
  expense: PoolExpense
  event: PoolEvent
  currentUserId: string | null
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

const hasParticipants = computed(() => {
  return (props.expense.participantIds ?? []).length > 0
})

interface ExpensePayer {
  name: string
  overlapDays: number
  share: number
}

const payers = computed((): ExpensePayer[] => {
  // If expense has explicit participants, equal split
  const participantIds = props.expense.participantIds ?? []
  if (participantIds.length > 0) {
    const participants = participantIds
      .map((pid) => pool.get('expenseParticipant', pid))
      .filter((p) => p != null)

    if (participants.length === 0) return []

    const share = props.expense.amount / participants.length
    return participants.map((p) => {
      const m = pool.findBy('member', 'userId', p.userId)
      return {
        name: m?.name ?? m?.email ?? 'Unknown',
        overlapDays: 0,
        share,
      }
    })
  }

  // Default: RSVP overlap logic
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

const deleting = ref(false)

async function handleDelete(e: Event) {
  e.stopPropagation()
  if (deleting.value) return
  deleting.value = true
  try {
    await expensesStore.deleteExpense(props.expense.id)
  } finally {
    deleting.value = false
  }
}
</script>

<template>
  <BaseCard
    data-testid="expense-row"
    interactive
    class="select-none"
    :aria-expanded="expanded"
    @click="toggleExpand"
  >
    <div class="flex items-center px-4 py-3">
      <div class="min-w-0 flex-1">
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
      </div>
      <div class="flex items-center gap-3">
        <span
          class="font-mono text-sm font-medium whitespace-nowrap text-gray-900 dark:text-white"
        >
          {{ formattedAmount }}
        </span>
        <div class="flex items-center gap-1">
          <LockClosedIcon
            v-if="isSettled"
            class="size-4 text-gray-400 dark:text-stone-500"
            title="Part of a settlement"
          />
          <template v-else>
            <IconButton
              v-if="isOwner"
              label="Edit expense"
              data-testid="edit-expense"
              @click="handleEdit"
            >
              <PencilIcon class="size-4" />
            </IconButton>
            <IconButton
              v-if="isOwner"
              variant="danger"
              label="Delete expense"
              :disabled="deleting"
              data-testid="delete-expense"
              @click="handleDelete"
            >
              <TrashIcon class="size-4" />
            </IconButton>
          </template>
          <ChevronDownIcon
            class="size-4 text-gray-400 transition-transform duration-200 dark:text-stone-500"
            :class="{ 'rotate-180': expanded }"
          />
        </div>
      </div>
    </div>

    <div
      v-if="expanded"
      data-testid="expense-detail"
      class="border-t border-gray-100 px-4 pt-3 pb-3 dark:border-stone-700"
    >
      <p
        v-if="payers.length === 0"
        class="text-xs text-gray-500 dark:text-stone-400"
      >
        No overlapping attendees for this expense.
      </p>
      <template v-else>
        <p
          v-if="hasParticipants"
          class="mb-1.5 text-xs font-medium text-amber-700 dark:text-amber-400"
        >
          Equal split
        </p>
        <table class="w-full text-xs">
          <thead>
            <tr class="text-left text-gray-500 uppercase dark:text-stone-400">
              <th class="pr-2 pb-1">Person</th>
              <th v-if="!hasParticipants" class="pr-2 pb-1">Days</th>
              <th class="pb-1 text-right">Share</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(payer, index) in payers"
              :key="index"
              class="text-gray-700 dark:text-stone-300"
            >
              <td
                class="max-w-[6rem] truncate py-0.5 pr-2 sm:max-w-[10rem]"
                :title="payer.name"
              >
                {{ payer.name }}
              </td>
              <td v-if="!hasParticipants" class="py-0.5 pr-2">
                {{ payer.overlapDays }}
              </td>
              <td class="py-0.5 text-right font-mono">
                €{{ payer.share.toFixed(2) }}
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>
  </BaseCard>
</template>
