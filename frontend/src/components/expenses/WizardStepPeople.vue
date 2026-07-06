<script setup lang="ts">
import { computed } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { attendedDates } from '@/utils/event'
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
  const eventStart = props.event.startDate
  const eventEnd = props.event.endDate
  if (!eventStart || !eventEnd) return []

  const attendingRsvps = pool
    .getAll('rsvp')
    .filter((r) => r.eventId === props.event.id && r.attending)

  return attendingRsvps
    .map((rsvp) => {
      const attended = attendedDates(rsvp, eventStart, eventEnd)
      const overlaps = attended.some(
        (d) => d >= props.startDate && d <= props.endDate
      )
      if (!overlaps) return null

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
      <p class="text-ink text-sm font-medium">Who is this for?</p>
      <div
        class="bg-btn-secondary-fill inline-flex gap-0.5 rounded-lg p-0.5"
        data-testid="toggle-people-mode"
      >
        <button
          type="button"
          class="focus-visible:outline-focus cursor-pointer rounded-md px-3 py-1.5 text-xs font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
          :class="
            everyone
              ? 'bg-amber-100 text-amber-800 shadow-sm dark:bg-amber-900/40 dark:text-amber-300'
              : 'text-ink-muted hover:bg-btn-secondary-fill-hover hover:text-ink'
          "
          @click="!everyone && toggleEveryone()"
        >
          Everyone
        </button>
        <button
          type="button"
          class="focus-visible:outline-focus cursor-pointer rounded-md px-3 py-1.5 text-xs font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
          :class="
            !everyone
              ? 'bg-amber-100 text-amber-800 shadow-sm dark:bg-amber-900/40 dark:text-amber-300'
              : 'text-ink-muted hover:bg-btn-secondary-fill-hover hover:text-ink'
          "
          @click="everyone && toggleEveryone()"
        >
          Specific people
        </button>
      </div>
    </div>

    <div v-if="everyone">
      <p class="text-ink-muted text-sm">
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
          class="bg-btn-secondary-fill text-btn-secondary-ink inline-block rounded-full px-2.5 py-0.5 text-xs"
        >
          {{ m.name }}
        </span>
      </div>
      <p v-else class="text-ink-muted mt-2 text-xs">
        No attending members overlap with this expense period.
      </p>
    </div>

    <div v-else>
      <p v-if="overlappingMembers.length === 0" class="text-ink-muted text-sm">
        No attending members overlap with this expense period. Go back and
        adjust the dates, or switch to Everyone.
      </p>
      <div v-else>
        <div class="space-y-1">
          <label
            v-for="m in overlappingMembers"
            :key="m.userId"
            class="focus-within:bg-surface-sunken hover:bg-surface-sunken flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2 transition-colors"
            :data-testid="`participant-${m.userId}`"
          >
            <input
              type="checkbox"
              class="border-line bg-surface size-4 rounded text-rose-500 focus:ring-rose-500"
              :checked="selectedUserIds.includes(m.userId)"
              @change="toggleUser(m.userId)"
            />
            <span class="text-ink flex-1 text-sm">
              {{ m.name }}
            </span>
            <div
              v-if="selectedUserIds.includes(m.userId)"
              class="flex items-center gap-1"
              :data-testid="`factor-${m.userId}`"
            >
              <button
                type="button"
                class="bg-btn-secondary-fill text-btn-secondary-ink enabled:hover:bg-btn-secondary-fill-hover focus-visible:outline-focus flex size-8 cursor-pointer items-center justify-center rounded-md transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-40"
                :disabled="!canDecrement(m.userId)"
                :aria-label="`Decrease factor for ${m.name}`"
                @click.prevent="adjustFactor(m.userId, -FACTOR_STEP)"
              >
                −
              </button>
              <span
                class="text-ink min-w-[2.25rem] text-center font-mono text-sm tabular-nums"
                :data-testid="`factor-value-${m.userId}`"
              >
                {{ formatFactor(factorFor(m.userId)) }}
              </span>
              <button
                type="button"
                class="bg-btn-secondary-fill text-btn-secondary-ink enabled:hover:bg-btn-secondary-fill-hover focus-visible:outline-focus flex size-8 cursor-pointer items-center justify-center rounded-md transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-40"
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
              : 'text-ink-muted'
          "
        >
          {{ selectedUserIds.length }} of
          {{ overlappingMembers.length }} selected
        </p>
        <p
          v-if="previewRows.length > 0"
          data-testid="share-preview"
          class="text-ink-muted mt-1 text-xs"
        >
          <span v-for="(row, i) in previewRows" :key="row.userId"
            >{{ i > 0 ? ' · ' : '' }}{{ row.name }}
            <LedgerAmount :amount="row.share"
          /></span>
          <span class="text-ink-muted">
            (of <LedgerAmount :amount="amount" />)
          </span>
        </p>
      </div>
    </div>
  </div>
</template>
