<script setup lang="ts">
import { computed } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { countDays } from '@/utils/event'
import LedgerAmount from '@/components/common/LedgerAmount.vue'
import type { PoolEvent, PoolMember } from '@/types/pool'

const props = defineProps<{
  event: PoolEvent
  startDate: string
  endDate: string
  everyone: boolean
  amount: number
}>()

const emit = defineEmits<{
  'update:everyone': [value: boolean]
}>()

const selectedUserIds = defineModel<string[]>('selectedUserIds', {
  required: true,
})
const factorByUserId = defineModel<Record<string, number>>('factorByUserId', {
  required: true,
})

const pool = useObjectPoolStore()

const FACTOR_MIN = 0.5
const FACTOR_MAX = 9.5
const FACTOR_STEP = 0.5

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
    factorByUserId.value = {}
  }
}

function toggleUser(userId: string): void {
  const current = selectedUserIds.value
  if (current.includes(userId)) {
    selectedUserIds.value = current.filter((id) => id !== userId)
    const next = { ...factorByUserId.value }
    delete next[userId]
    factorByUserId.value = next
  } else {
    selectedUserIds.value = [...current, userId]
    factorByUserId.value = { ...factorByUserId.value, [userId]: 1 }
  }
}

function factorFor(userId: string): number {
  return factorByUserId.value[userId] ?? 1
}

function adjustFactor(userId: string, delta: number): void {
  const current = factorFor(userId)
  const next = Math.round((current + delta) / FACTOR_STEP) * FACTOR_STEP
  if (next < FACTOR_MIN - 1e-9 || next > FACTOR_MAX + 1e-9) return
  factorByUserId.value = { ...factorByUserId.value, [userId]: next }
}

function formatFactor(factor: number): string {
  if (factor === Math.floor(factor)) return String(factor)
  const whole = Math.floor(factor)
  return whole === 0 ? '½' : `${whole}½`
}

const canDecrement = (userId: string) => factorFor(userId) > FACTOR_MIN + 1e-9
const canIncrement = (userId: string) => factorFor(userId) < FACTOR_MAX - 1e-9

const previewRows = computed(() => {
  if (props.everyone) return []
  const selected = selectedUserIds.value
  if (selected.length === 0 || !(props.amount > 0)) return []

  const totalFactor = selected.reduce((s, uid) => s + factorFor(uid), 0)
  if (totalFactor <= 0) return []

  return selected.map((uid) => {
    const m = overlappingMembers.value.find((o) => o.userId === uid)
    return {
      userId: uid,
      name: m?.name ?? 'Unknown',
      share: (factorFor(uid) / totalFactor) * props.amount,
    }
  })
})
</script>

<template>
  <div>
    <div class="mb-3 flex flex-wrap items-center justify-between gap-2">
      <p class="text-sm font-medium text-gray-700 dark:text-stone-300">
        Who is this for?
      </p>
      <div
        class="inline-flex gap-0.5 rounded-lg bg-gray-100 p-0.5 dark:bg-stone-700"
        data-testid="toggle-people-mode"
      >
        <button
          type="button"
          class="rounded-md px-3 py-1.5 text-xs font-medium transition-colors"
          :class="
            everyone
              ? 'bg-amber-100 text-amber-800 shadow-sm dark:bg-amber-900/40 dark:text-amber-300'
              : 'text-gray-500 hover:bg-gray-200 hover:text-gray-700 dark:text-stone-400 dark:hover:bg-stone-600 dark:hover:text-stone-200'
          "
          @click="!everyone && toggleEveryone()"
        >
          Everyone
        </button>
        <button
          type="button"
          class="rounded-md px-3 py-1.5 text-xs font-medium transition-colors"
          :class="
            !everyone
              ? 'bg-amber-100 text-amber-800 shadow-sm dark:bg-amber-900/40 dark:text-amber-300'
              : 'text-gray-500 hover:bg-gray-200 hover:text-gray-700 dark:text-stone-400 dark:hover:bg-stone-600 dark:hover:text-stone-200'
          "
          @click="everyone && toggleEveryone()"
        >
          Specific people
        </button>
      </div>
    </div>

    <div v-if="everyone">
      <p class="text-sm text-gray-500 dark:text-stone-400">
        Split by attendance overlap — everyone who RSVPs will be included
        automatically.
      </p>
      <div
        v-if="overlappingMembers.length > 0"
        class="mt-2 flex flex-wrap gap-1.5"
      >
        <span
          v-for="m in overlappingMembers"
          :key="m.userId"
          class="inline-block rounded-full bg-gray-100 px-2.5 py-0.5 text-xs text-gray-700 dark:bg-stone-700 dark:text-stone-300"
        >
          {{ m.name }}
        </span>
      </div>
      <p v-else class="mt-2 text-xs text-gray-400 dark:text-stone-500">
        No attending members overlap with this expense period.
      </p>
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
            <span class="flex-1 text-sm text-gray-900 dark:text-white">
              {{ m.name }}
            </span>
            <div
              v-if="selectedUserIds.includes(m.userId)"
              class="flex items-center gap-1"
              :data-testid="`factor-${m.userId}`"
            >
              <button
                type="button"
                class="flex size-8 items-center justify-center rounded-md bg-gray-200 text-gray-700 enabled:hover:bg-gray-300 disabled:opacity-40 dark:bg-stone-700 dark:text-stone-200 dark:enabled:hover:bg-stone-600"
                :disabled="!canDecrement(m.userId)"
                :aria-label="`Decrease factor for ${m.name}`"
                @click.prevent="adjustFactor(m.userId, -FACTOR_STEP)"
              >
                −
              </button>
              <span
                class="min-w-[2.25rem] text-center font-mono text-sm text-gray-900 tabular-nums dark:text-white"
                :data-testid="`factor-value-${m.userId}`"
              >
                {{ formatFactor(factorFor(m.userId)) }}
              </span>
              <button
                type="button"
                class="flex size-8 items-center justify-center rounded-md bg-gray-200 text-gray-700 enabled:hover:bg-gray-300 disabled:opacity-40 dark:bg-stone-700 dark:text-stone-200 dark:enabled:hover:bg-stone-600"
                :disabled="!canIncrement(m.userId)"
                :aria-label="`Increase factor for ${m.name}`"
                @click.prevent="adjustFactor(m.userId, FACTOR_STEP)"
              >
                +
              </button>
            </div>
          </label>
        </div>
        <p
          class="mt-2 text-xs"
          :class="
            selectedUserIds.length > 0
              ? 'text-amber-700 dark:text-amber-400'
              : 'text-gray-500 dark:text-stone-400'
          "
        >
          {{ selectedUserIds.length }} of
          {{ overlappingMembers.length }} selected
        </p>
        <p
          v-if="previewRows.length > 0"
          data-testid="share-preview"
          class="mt-1 text-xs text-gray-600 dark:text-stone-400"
        >
          <span v-for="(row, i) in previewRows" :key="row.userId"
            >{{ i > 0 ? ' · ' : '' }}{{ row.name }}
            <LedgerAmount :amount="row.share"
          /></span>
          <span class="text-gray-400 dark:text-stone-500">
            (of <LedgerAmount :amount="amount" />)
          </span>
        </p>
      </div>
    </div>
  </div>
</template>
