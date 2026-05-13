<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  TrashIcon,
  ChevronDownIcon,
  PencilIcon,
  LockClosedIcon,
  ArrowUturnLeftIcon,
} from '@heroicons/vue/24/outline'
import IconButton from '@/components/common/IconButton.vue'
import LedgerAmount from '@/components/common/LedgerAmount.vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useExpensesStore } from '@/stores/expenses'
import { countDays } from '@/utils/event'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import type { PoolExpense, PoolEvent } from '@/types/pool'
import BaseCard from '@/components/common/BaseCard.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import AppButton from '@/components/common/AppButton.vue'
import { permissionUx } from '@/composables/usePermission'
import { useUndoDelete } from '@/composables/useUndoDelete'

const props = defineProps<{
  expense: PoolExpense
  event: PoolEvent
  currentUserId: string | null
}>()

const pool = useObjectPoolStore()
const expensesStore = useExpensesStore()
const { undoableDelete } = useUndoDelete()

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

const filedOnBehalf = computed(() => {
  const filer = props.expense.createdByUserId
  return filer != null && filer !== props.expense.userId
})

const filedByName = computed(() => {
  if (!filedOnBehalf.value) return null
  const m = pool.findBy('member', 'userId', props.expense.createdByUserId)
  return m?.name || m?.email || 'Unknown'
})

const editUx = computed(() => permissionUx(props.expense.permissions, 'edit'))
const deleteUx = computed(() =>
  permissionUx(props.expense.permissions, 'delete')
)
const revertUx = computed(() =>
  permissionUx(props.expense.permissions, 'revert')
)

const isSettled = computed(() => {
  return !!props.expense.settlementId
})

const isRevert = computed(() => !!props.expense.revertsExpenseId)

const hasBeenReverted = computed(() =>
  pool.getAll('expense').some((e) => e.revertsExpenseId === props.expense.id)
)

const revertedOriginal = computed(() =>
  isRevert.value ? pool.get('expense', props.expense.revertsExpenseId!) : null
)

const hasParticipants = computed(() => {
  return (props.expense.participantIds ?? []).length > 0
})

const hasUnequalFactors = computed(() => {
  if (!hasParticipants.value) return false
  const ids = props.expense.participantIds ?? []
  return ids
    .map((pid) => pool.get('expenseParticipant', pid))
    .some((p) => p != null && p.factor !== 1)
})

const participantsHeading = computed(() =>
  hasUnequalFactors.value ? 'Custom split' : 'Equal split'
)

function formatFactor(factor: number): string {
  if (factor === Math.floor(factor)) return `×${factor}`
  // Render half-steps with ½
  const whole = Math.floor(factor)
  const frac =
    factor - whole === 0.5 ? '½' : `.${Math.round((factor - whole) * 10)}`
  return whole === 0 ? `×${frac}` : `×${whole}${frac}`
}

interface ExpensePayer {
  name: string
  overlapDays: number
  share: number
  factor?: number
}

const payers = computed((): ExpensePayer[] => {
  // If expense has explicit participants, factor-weighted split
  const participantIds = props.expense.participantIds ?? []
  if (participantIds.length > 0) {
    const participants = participantIds
      .map((pid) => pool.get('expenseParticipant', pid))
      .filter((p) => p != null)

    if (participants.length === 0) return []

    const totalFactor = participants.reduce((s, p) => s + p.factor, 0)
    return participants.map((p) => {
      const m = pool.findBy('member', 'userId', p.userId)
      const share =
        totalFactor > 0 ? (p.factor / totalFactor) * props.expense.amount : 0
      return {
        name: m?.name ?? m?.email ?? 'Unknown',
        overlapDays: 0,
        share,
        factor: p.factor,
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

const blockedActionMessage = ref('')
const showBlockedActionModal = ref(false)

function explainBlocked(message: string) {
  blockedActionMessage.value = message
  showBlockedActionModal.value = true
}

function handleEdit(e: Event) {
  e.stopPropagation()
  if (editUx.value.behavior === 'modal') {
    explainBlocked(editUx.value.message)
    return
  }
  if (editUx.value.behavior !== 'enabled') return
  emit('edit', props.expense)
}

const showRevertConfirm = ref(false)
const reverting = ref(false)

function handleRevertClick(e: Event) {
  e.stopPropagation()
  showRevertConfirm.value = true
}

const revertError = ref<string | null>(null)

async function confirmRevert() {
  if (reverting.value) return
  reverting.value = true
  revertError.value = null
  try {
    await expensesStore.revertExpense(props.expense.id)
    showRevertConfirm.value = false
  } catch (err) {
    revertError.value =
      err instanceof Error ? err.message : 'Failed to revert expense'
  } finally {
    reverting.value = false
  }
}

function closeRevertModal() {
  showRevertConfirm.value = false
  revertError.value = null
}

function handleDelete(e: Event) {
  e.stopPropagation()
  if (deleteUx.value.behavior === 'modal') {
    explainBlocked(deleteUx.value.message)
    return
  }
  if (deleteUx.value.behavior !== 'enabled') return
  undoableDelete({
    objectType: 'expense',
    objectId: props.expense.id,
    message: 'Expense deleted',
    apiPath: `/expenses/${props.expense.id}`,
  })
}
</script>

<template>
  <BaseCard
    data-testid="expense-row"
    interactive
    :class="['select-none', hasBeenReverted ? 'opacity-60' : '']"
    :aria-expanded="expanded"
    @click="toggleExpand"
  >
    <div class="flex items-center px-4 py-3">
      <div class="min-w-0 flex-1">
        <p
          :class="[
            'truncate text-base text-gray-900 dark:text-white',
            hasBeenReverted ? 'line-through' : '',
          ]"
        >
          {{ expense.description }}
        </p>
        <p class="mt-0.5 truncate text-xs text-gray-500 dark:text-stone-400">
          <span
            v-if="isRevert"
            class="mr-1 font-medium text-amber-700 dark:text-amber-400"
          >
            Reverts
            <template v-if="revertedOriginal">
              “{{ revertedOriginal.description }}”
            </template>
            ·
          </span>
          <span
            v-else-if="hasBeenReverted"
            class="mr-1 font-medium text-amber-700 dark:text-amber-400"
          >
            Reverted ·
          </span>
          {{ displayName }}
          <span
            v-if="filedOnBehalf"
            class="ml-1 text-gray-400 dark:text-stone-500"
            data-testid="filed-by"
          >
            (filed by {{ filedByName }})
          </span>
          <template v-if="event.startDate && event.endDate">
            <span aria-hidden="true" class="text-gray-300 dark:text-stone-600">
              ·
            </span>
            <DateRangeDisplay
              :start-date="expense.startDate"
              :end-date="expense.endDate"
            />
          </template>
        </p>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-sm font-medium whitespace-nowrap text-gray-900 dark:text-white">
          <LedgerAmount :amount="expense.amount" />
        </span>
        <div class="flex items-center gap-1">
          <LockClosedIcon
            v-if="isSettled"
            class="size-4 text-gray-400 dark:text-stone-500"
            title="Part of a settlement"
          />
          <IconButton
            v-if="revertUx.behavior === 'enabled' && !hasBeenReverted"
            label="Revert expense"
            data-testid="revert-expense"
            title="Reverse this expense with a mirror-image entry"
            @click="handleRevertClick"
          >
            <ArrowUturnLeftIcon class="size-4" />
          </IconButton>
          <span
            v-if="editUx.behavior !== 'hidden'"
            :title="editUx.behavior === 'disabled' ? editUx.tooltip : undefined"
          >
            <IconButton
              label="Edit expense"
              data-testid="edit-expense"
              :disabled="editUx.behavior === 'disabled'"
              @click="handleEdit"
            >
              <PencilIcon class="size-4" />
            </IconButton>
          </span>
          <span
            v-if="deleteUx.behavior !== 'hidden'"
            :title="
              deleteUx.behavior === 'disabled' ? deleteUx.tooltip : undefined
            "
          >
            <IconButton
              variant="danger"
              label="Delete expense"
              :disabled="deleteUx.behavior === 'disabled'"
              data-testid="delete-expense"
              @click="handleDelete"
            >
              <TrashIcon class="size-4" />
            </IconButton>
          </span>
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
        No one was attending on these dates.
      </p>
      <template v-else>
        <p
          v-if="hasParticipants"
          class="mb-1.5 text-xs font-medium text-gray-500 dark:text-stone-400"
        >
          {{ participantsHeading }}
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
                <span
                  v-if="payer.factor != null && payer.factor !== 1"
                  class="ml-1 text-gray-500 dark:text-stone-400"
                >
                  {{ formatFactor(payer.factor) }}
                </span>
              </td>
              <td v-if="!hasParticipants" class="py-0.5 pr-2">
                {{ payer.overlapDays }}
              </td>
              <td class="py-0.5 text-right">
                <LedgerAmount :amount="payer.share" />
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>
  </BaseCard>

  <BaseModal
    :open="showRevertConfirm"
    title="Revert this expense?"
    size="sm"
    @close="closeRevertModal"
  >
    <p class="text-sm text-gray-600 dark:text-stone-400">
      This adds a mirror-image entry of
      <LedgerAmount :amount="expense.amount" /> that offsets the original. The
      reverted expense stays visible for history. If
      you want to re-enter it with different details, add a new expense
      afterwards.
    </p>
    <p
      v-if="revertError"
      role="alert"
      class="mt-3 text-sm text-red-600 dark:text-red-400"
    >
      {{ revertError }}
    </p>
    <div class="mt-6 flex justify-end gap-3">
      <AppButton
        variant="secondary"
        size="sm"
        :disabled="reverting"
        @click="closeRevertModal"
      >
        Cancel
      </AppButton>
      <AppButton
        size="sm"
        :loading="reverting"
        loading-label="Reverting…"
        data-testid="confirm-revert-expense"
        @click="confirmRevert"
      >
        Revert
      </AppButton>
    </div>
  </BaseModal>

  <BaseModal
    :open="showBlockedActionModal"
    title="Can't change this expense"
    size="sm"
    data-testid="expense-blocked-modal"
    @close="showBlockedActionModal = false"
  >
    <p class="text-sm text-gray-600 dark:text-stone-400">
      {{ blockedActionMessage }}
    </p>
    <div class="mt-6 flex justify-end">
      <AppButton
        variant="secondary"
        size="sm"
        @click="showBlockedActionModal = false"
      >
        OK
      </AppButton>
    </div>
  </BaseModal>
</template>
