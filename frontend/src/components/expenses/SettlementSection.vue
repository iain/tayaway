<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  BanknotesIcon,
  CalculatorIcon,
  CheckCircleIcon,
  ChevronDownIcon,
  CurrencyEuroIcon,
  LockClosedIcon,
  ScaleIcon,
  QrCodeIcon,
  TrashIcon,
} from '@heroicons/vue/24/outline'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useSettlementsStore } from '@/stores/settlements'
import {
  computeBalances,
  computeDriftBalances,
  minimizeTransfers,
  annotateTransfers,
  deriveBalancesFromTransfers,
  type PreviewTransfer,
  type AnnotatedTransfer,
} from '@/utils/settlement'
import TimeAnchor from '@/components/common/TimeAnchor.vue'
import LedgerAmount from '@/components/common/LedgerAmount.vue'
import { getMemberName } from '@/utils/member'
import AppButton from '@/components/common/AppButton.vue'
import AppBadge from '@/components/common/AppBadge.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import IconButton from '@/components/common/IconButton.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import EpcQrModal from '@/components/expenses/EpcQrModal.vue'
import SettlementMath from '@/components/expenses/SettlementMath.vue'
import type { PoolSettlement, PoolSettlementTransfer } from '@/types/pool'
import type { HydratedEvent } from '@/composables/useHydratedEvent'
import {
  can,
  permissionUx,
  type PermissionUx,
} from '@/composables/usePermission'

const props = defineProps<{
  event: HydratedEvent
  currentUserId: string | null
}>()

const pool = useObjectPoolStore()
const settlementsStore = useSettlementsStore()

const settlements = computed(() =>
  pool
    .getAll('settlement')
    .filter((s) => s.eventId === props.event.id)
    .sort(
      (a, b) =>
        b.createdAt.localeCompare(a.createdAt) || a.id.localeCompare(b.id)
    )
)

const unsettledExpenseCount = computed(
  () =>
    pool
      .getAll('expense')
      .filter((e) => e.eventId === props.event.id && !e.settlementId).length
)

const hasExpenses = computed(
  () =>
    pool.getAll('expense').filter((e) => e.eventId === props.event.id).length >
    0
)

function showDeleteSettlement(settlement: PoolSettlement): boolean {
  // Render the button for anything that isn't outright hidden — `modal`
  // surfaces an explanation when the user clicks (e.g. older settlements
  // with `:not_tip`).
  return permissionUx(settlement.permissions, 'delete').behavior !== 'hidden'
}

function transfersForSettlement(settlementId: string) {
  // Pool order is arrival order, which differs between IndexedDB hydration,
  // full sync, and live broadcasts — sort so the list is stable.
  return pool
    .getAll('settlementTransfer')
    .filter((t) => t.settlementId === settlementId)
    .sort((a, b) => b.amount - a.amount || a.id.localeCompare(b.id))
}

function activeTransfersForSettlement(settlementId: string) {
  return transfersForSettlement(settlementId).filter((t) => !t.supersededAt)
}

function allTransfersPaid(settlementId: string): boolean {
  const transfers = activeTransfersForSettlement(settlementId)
  return transfers.length > 0 && transfers.every((t) => t.paidAt !== null)
}

const showPreviewModal = ref(false)
const settling = ref(false)
const previewMathOpen = ref(false)

const hasTip = computed(() => settlements.value.length > 0)

const activeTransfersInChain = computed(() =>
  settlements.value
    .flatMap((s) => transfersForSettlement(s.id))
    .filter((t) => !t.supersededAt)
)

const paidTransfersInChain = computed(() =>
  activeTransfersInChain.value.filter((t) => t.paidAt !== null)
)

const resolveParticipant = (pid: string) => {
  const p = pool.get('expenseParticipant', pid)
  return p ? { userId: p.userId, factor: p.factor } : undefined
}

// Top-up-aware preview: when a tip exists, balances reflect the drift between
// what has already been settled (sum of prior transfers) and what fair shares
// would be right now for every expense in the event. When there's no tip,
// this is just the first-settlement balance over unsettled expenses.
// Going attendances resolved to their billing users via the hydrated
// attendee — the settlement math never looks inside the user/guest union.
const billableAttendances = computed(() =>
  props.event.attendances
    .filter((a) => a.status === 'going')
    .map((a) => ({
      status: a.status,
      days: a.days,
      billingUserId: a.attendee.billingUserId,
    }))
)

const previewBalances = computed((): Map<string, number> => {
  if (!props.event.startDate || !props.event.endDate) return new Map()
  if (billableAttendances.value.length === 0) return new Map()

  if (hasTip.value) {
    const allExpenses = pool
      .getAll('expense')
      .filter((e) => e.eventId === props.event.id)
    if (allExpenses.length === 0) return new Map()
    const currentBalances = computeBalances(
      allExpenses,
      billableAttendances.value,
      props.event.startDate,
      props.event.endDate,
      resolveParticipant
    )
    return computeDriftBalances(currentBalances, paidTransfersInChain.value)
  }

  const unsettledExpenses = pool
    .getAll('expense')
    .filter((e) => e.eventId === props.event.id && !e.settlementId)
  if (unsettledExpenses.length === 0) return new Map()
  return computeBalances(
    unsettledExpenses,
    billableAttendances.value,
    props.event.startDate,
    props.event.endDate,
    resolveParticipant
  )
})

const previewTransfers = computed((): PreviewTransfer[] => {
  return minimizeTransfers(previewBalances.value)
})

// Drift is about whether the underlying split has changed since the latest
// settlement was locked in — not whether its transfers happen to be unpaid.
// Subtract every active transfer (paid or not) from the current fair share
// and see whether anything is left that could fund a transfer. Per-user
// residuals can survive the half-cent epsilon as rounding crumbs from the
// last top-up; only a residual that produces a real transfer counts.
const hasDrift = computed(() => {
  if (!hasTip.value) return false
  if (!props.event.startDate || !props.event.endDate) return false
  if (billableAttendances.value.length === 0) return false
  const allExpenses = pool
    .getAll('expense')
    .filter((e) => e.eventId === props.event.id)
  if (allExpenses.length === 0) return false
  const currentBalances = computeBalances(
    allExpenses,
    billableAttendances.value,
    props.event.startDate,
    props.event.endDate,
    resolveParticipant
  )
  const residual = computeDriftBalances(
    currentBalances,
    activeTransfersInChain.value
  )
  return minimizeTransfers(residual).length > 0
})

const showCta = computed(
  () => unsettledExpenseCount.value > 0 || hasDrift.value
)

const ctaLabel = computed(() => {
  if (!hasTip.value) return 'Start settlement'
  if (unsettledExpenseCount.value > 0) return 'Top up settlement'
  return 'Settle the difference'
})

const previewAnnotatedTransfers = computed((): AnnotatedTransfer[] => {
  return annotateTransfers(
    previewTransfers.value,
    previewBalances.value,
    (userId) => getMemberName(userId, pool)
  )
})

const openMathSettlementIds = ref(new Set<string>())

function toggleSettlementMath(id: string) {
  const next = new Set(openMathSettlementIds.value)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  openMathSettlementIds.value = next
}

function isSettlementMathOpen(id: string): boolean {
  return openMathSettlementIds.value.has(id)
}

function balancesForSettlement(settlementId: string): Map<string, number> {
  return deriveBalancesFromTransfers(transfersForSettlement(settlementId))
}

function annotatedTransfersForSettlement(
  settlementId: string
): AnnotatedTransfer[] {
  return annotateTransfers(
    transfersForSettlement(settlementId),
    balancesForSettlement(settlementId),
    (uid) => getMemberName(uid, pool)
  )
}

function openPreview() {
  showPreviewModal.value = true
}

async function confirmSettle() {
  settling.value = true
  try {
    await settlementsStore.createSettlement(props.event.id)
    showPreviewModal.value = false
  } finally {
    settling.value = false
  }
}

const settlementToDelete = ref<PoolSettlement | null>(null)
const deletingSettlement = ref(false)

function handleDeleteSettlement(settlement: PoolSettlement) {
  const ux = permissionUx(settlement.permissions, 'delete')
  if (ux.behavior === 'modal') {
    blockedActionMessage.value = ux.message
    showBlockedActionModal.value = true
    return
  }
  if (ux.behavior !== 'enabled') return
  settlementToDelete.value = settlement
}

async function confirmDeleteSettlement() {
  if (!settlementToDelete.value || deletingSettlement.value) return
  deletingSettlement.value = true
  try {
    await settlementsStore.deleteSettlement(settlementToDelete.value.id)
    settlementToDelete.value = null
  } finally {
    deletingSettlement.value = false
  }
}

const showBlockedActionModal = ref(false)

const showQrModal = ref(false)
const qrTransferId = ref<string | null>(null)
const qrRecipientName = ref<string | null>(null)
const qrAmount = ref<number | null>(null)

function openQrModal(transfer: {
  id: string
  toUserId: string | null
  amount: number
}) {
  if (!transfer.toUserId) return
  const member = pool.findBy('member', 'userId', transfer.toUserId)
  qrTransferId.value = transfer.id
  qrRecipientName.value = member?.name ?? member?.email ?? null
  qrAmount.value = transfer.amount
  showQrModal.value = true
}

const blockedActionMessage = ref('')

function markPaidUx(transfer: PoolSettlementTransfer): PermissionUx {
  return permissionUx(transfer.permissions, 'mark_paid')
}

async function handlePaidClick(
  transfer: PoolSettlementTransfer,
  currentlyPaid: boolean
) {
  const ux = markPaidUx(transfer)
  if (ux.behavior === 'modal') {
    blockedActionMessage.value = ux.message
    showBlockedActionModal.value = true
    return
  }
  if (ux.behavior !== 'enabled') return
  await settlementsStore.markTransferPaid(transfer.id, !currentlyPaid)
}
</script>

<template>
  <div v-if="event.startDate && event.endDate" class="mt-10">
    <SectionHeading :icon="BanknotesIcon" title="Settlements">
      <AppButton
        v-if="showCta"
        data-testid="start-settlement-button"
        @click="openPreview"
      >
        <ScaleIcon class="size-4" />
        {{ ctaLabel }}
        <span v-if="unsettledExpenseCount > 0" class="text-rose-200">
          ({{ unsettledExpenseCount }})
        </span>
      </AppButton>
    </SectionHeading>

    <div
      v-if="hasDrift && unsettledExpenseCount === 0"
      data-testid="settlement-drift-banner"
      class="bg-state-warning-fill mb-4 rounded-md border-2 border-dashed border-amber-400 px-3 py-2 dark:border-amber-600"
    >
      <p class="text-state-warning-ink text-sm font-medium">
        The split no longer matches the latest settlement.
      </p>
      <p class="text-state-warning-ink mt-1 text-xs">
        RSVPs or expenses have changed since it was locked in. Settle the
        difference to bring everyone back to even.
      </p>
    </div>

    <div
      v-if="settlements.length === 0 && !hasExpenses"
      class="border-line bg-surface-sunken rounded-lg border p-4"
    >
      <p class="text-ink mb-3 text-sm font-medium">How settling up works</p>
      <ol class="space-y-3">
        <li class="flex items-start gap-3">
          <span
            class="flex size-6 shrink-0 items-center justify-center rounded-full bg-gray-300 text-white dark:bg-stone-600"
          >
            <CurrencyEuroIcon class="size-3.5" />
          </span>
          <span class="text-ink-muted text-sm">
            <span class="text-ink font-medium">Log expenses</span>
            &mdash; everyone adds what they paid for. Costs are split per day
            among attendees.
          </span>
        </li>
        <li class="flex items-start gap-3">
          <span
            class="flex size-6 shrink-0 items-center justify-center rounded-full bg-gray-300 dark:bg-stone-600"
          >
            <CalculatorIcon class="size-3.5 text-white" />
          </span>
          <span class="text-ink-muted text-sm">
            <span class="text-ink font-medium">Start settlement</span>
            &mdash; see who owes whom, then lock it in. Locked expenses can no
            longer be edited.
          </span>
        </li>
        <li class="flex items-start gap-3">
          <span
            class="flex size-6 shrink-0 items-center justify-center rounded-full bg-gray-300 dark:bg-stone-600"
          >
            <BanknotesIcon class="size-3.5 text-white" />
          </span>
          <span class="text-ink-muted text-sm">
            <span class="text-ink font-medium">Pay up</span>
            &mdash; transfer money via your banking app. When someone you owe
            has added their IBAN in
            <router-link
              to="/settings/payment"
              class="font-medium text-rose-600 hover:text-rose-500 dark:text-rose-400 dark:hover:text-rose-300"
              >their settings</router-link
            >, a QR code appears that pre-fills the amount, recipient, and
            reference &mdash; no copy-pasting account numbers.
          </span>
        </li>
        <li class="flex items-start gap-3">
          <span
            class="flex size-6 shrink-0 items-center justify-center rounded-full bg-gray-300 dark:bg-stone-600"
          >
            <CheckCircleIcon class="size-3.5 text-white" />
          </span>
          <span class="text-ink-muted text-sm">
            <span class="text-ink font-medium">Mark as paid</span>
            &mdash; once the money arrives, the recipient marks the transfer as
            paid so everyone can see what&rsquo;s left.
          </span>
        </li>
      </ol>
    </div>

    <BaseCard
      v-for="settlement in settlements"
      :key="settlement.id"
      class="mb-4 overflow-hidden"
    >
      <div
        class="border-line-faint flex flex-wrap items-center justify-between gap-y-1 border-b px-3 py-2"
      >
        <div class="flex min-w-0 items-center gap-2">
          <span class="text-ink-muted text-xs">
            <span v-if="settlement.previousSettlementId">Top-up</span>
            <span v-else>Settled</span>
            by {{ getMemberName(settlement.userId, pool) }}
            <TimeAnchor :at="settlement.createdAt" />
          </span>
          <AppBadge v-if="allTransfersPaid(settlement.id)" variant="success">
            <CheckCircleIcon class="size-3" />
            All paid
          </AppBadge>
        </div>
        <IconButton
          v-if="showDeleteSettlement(settlement)"
          variant="danger"
          label="Delete settlement"
          data-testid="delete-settlement-button"
          @click="handleDeleteSettlement(settlement)"
        >
          <TrashIcon class="size-4" />
        </IconButton>
      </div>

      <div
        v-if="transfersForSettlement(settlement.id).length > 0"
        class="border-line-faint border-b px-3 py-1.5"
      >
        <button
          type="button"
          class="text-ink-muted hover:bg-btn-secondary-fill focus-visible:outline-focus flex w-full cursor-pointer items-center justify-between rounded-md px-1.5 py-1 text-xs transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
          :data-testid="`settlement-math-toggle-${settlement.id}`"
          :aria-expanded="isSettlementMathOpen(settlement.id)"
          :aria-controls="`settlement-math-panel-${settlement.id}`"
          @click="toggleSettlementMath(settlement.id)"
        >
          <span>
            {{
              isSettlementMathOpen(settlement.id)
                ? 'Hide breakdown'
                : 'Show breakdown'
            }}
          </span>
          <ChevronDownIcon
            class="size-4 transition-transform"
            :class="{ 'rotate-180': isSettlementMathOpen(settlement.id) }"
            aria-hidden="true"
          />
        </button>
        <div
          v-if="isSettlementMathOpen(settlement.id)"
          :id="`settlement-math-panel-${settlement.id}`"
          class="mt-2"
        >
          <SettlementMath
            :balances="balancesForSettlement(settlement.id)"
            :transfers="annotatedTransfersForSettlement(settlement.id)"
            :name-for="(uid) => getMemberName(uid, pool)"
          />
        </div>
      </div>

      <div class="divide-line-faint divide-y">
        <div
          v-for="transfer in transfersForSettlement(settlement.id)"
          :key="transfer.id"
          data-testid="transfer-row"
          class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 px-4 py-3"
          :class="{
            'opacity-60': transfer.supersededAt,
          }"
        >
          <div class="flex min-w-0 items-center gap-2">
            <span
              class="text-ink truncate text-sm"
              :class="{ 'line-through': transfer.supersededAt }"
            >
              {{ getMemberName(transfer.fromUserId, pool) }}
            </span>
            <span class="text-ink-muted shrink-0 text-xs"> &rarr; </span>
            <span
              class="text-ink truncate text-sm"
              :class="{ 'line-through': transfer.supersededAt }"
            >
              {{ getMemberName(transfer.toUserId, pool) }}
            </span>
            <span
              class="text-ink shrink-0 text-sm font-semibold"
              :class="{ 'line-through': transfer.supersededAt }"
            >
              <LedgerAmount :amount="transfer.amount" />
            </span>
            <AppBadge v-if="transfer.supersededAt" variant="neutral">
              Superseded
            </AppBadge>
          </div>
          <div v-if="!transfer.supersededAt" class="flex items-center gap-2">
            <AppButton
              v-if="
                !transfer.paidAt && can(transfer.permissions, 'generate_qr')
              "
              variant="secondary"
              size="sm"
              title="Show QR code for bank transfer"
              @click="openQrModal(transfer)"
            >
              <QrCodeIcon class="size-4" aria-hidden="true" />
              Pay via QR
            </AppButton>
            <button
              type="button"
              class="inline-flex min-h-[44px] cursor-pointer items-center justify-center rounded-md px-3 py-1.5 text-sm font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 sm:min-h-0"
              :class="
                transfer.paidAt
                  ? 'bg-state-success-fill text-state-success-ink hover:bg-green-200 focus-visible:outline-green-500 dark:hover:bg-green-900/50'
                  : 'bg-primary text-primary-ink hover:bg-primary-hover shadow-sm focus-visible:outline-rose-600'
              "
              @click="handlePaidClick(transfer, !!transfer.paidAt)"
            >
              {{ transfer.paidAt ? 'Paid' : 'Mark as paid' }}
            </button>
          </div>
        </div>
      </div>
    </BaseCard>

    <BaseModal
      v-if="showPreviewModal"
      :open="showPreviewModal"
      :title="hasTip ? 'Top-up Preview' : 'Settlement Preview'"
      size="md"
      @close="showPreviewModal = false"
    >
      <p class="text-ink-muted mb-4 flex items-center gap-2 text-sm">
        <AppBadge variant="neutral">Preview</AppBadge>
        Nothing has been settled yet.
      </p>

      <p v-if="unsettledExpenseCount > 0" class="text-ink-muted mb-3 text-sm">
        {{ unsettledExpenseCount }}
        expense{{ unsettledExpenseCount === 1 ? '' : 's' }} will be locked to
        this settlement.
      </p>
      <p v-else-if="hasTip" class="text-ink-muted mb-3 text-sm">
        This top-up covers the drift since the last settlement — no new expenses
        are being locked.
      </p>

      <div v-if="previewTransfers.length > 0" class="mb-3">
        <button
          type="button"
          class="text-ink-muted hover:bg-btn-secondary-fill focus-visible:outline-focus flex w-full cursor-pointer items-center justify-between rounded-md px-2 py-1 text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
          data-testid="preview-math-toggle"
          :aria-expanded="previewMathOpen"
          aria-controls="preview-math-panel"
          @click="previewMathOpen = !previewMathOpen"
        >
          <span>{{
            previewMathOpen ? 'Hide breakdown' : 'Show breakdown'
          }}</span>
          <ChevronDownIcon
            class="size-4 transition-transform"
            :class="{ 'rotate-180': previewMathOpen }"
            aria-hidden="true"
          />
        </button>
        <div v-if="previewMathOpen" id="preview-math-panel" class="mt-2">
          <SettlementMath
            :balances="previewBalances"
            :transfers="previewAnnotatedTransfers"
            :name-for="(uid) => getMemberName(uid, pool)"
          />
        </div>
      </div>

      <div
        v-if="previewTransfers.length > 0 && !previewMathOpen"
        class="border-line overflow-hidden rounded-lg border border-dashed"
      >
        <div class="divide-line-faint divide-y">
          <div
            v-for="(transfer, i) in previewTransfers"
            :key="i"
            class="flex items-center gap-2 px-3 py-2"
          >
            <span class="text-ink truncate text-sm">
              {{ getMemberName(transfer.fromUserId, pool) }}
            </span>
            <span class="text-ink-muted shrink-0 text-xs"> &rarr; </span>
            <span class="text-ink truncate text-sm">
              {{ getMemberName(transfer.toUserId, pool) }}
            </span>
            <span class="text-ink ml-auto shrink-0 text-sm font-medium">
              <LedgerAmount :amount="transfer.amount" />
            </span>
          </div>
        </div>
      </div>

      <p
        v-else-if="previewTransfers.length === 0"
        class="text-ink-muted text-sm"
      >
        All balances are settled &mdash; no transfers needed.
      </p>

      <div class="mt-6 flex justify-end gap-3">
        <AppButton
          variant="secondary"
          size="sm"
          @click="showPreviewModal = false"
        >
          Cancel
        </AppButton>
        <AppButton
          size="sm"
          :loading="settling"
          loading-label="Settling..."
          @click="confirmSettle"
        >
          <LockClosedIcon class="size-4" />
          Confirm &amp; Settle
        </AppButton>
      </div>
    </BaseModal>

    <BaseModal
      :open="showBlockedActionModal"
      title="Can't do that right now"
      size="sm"
      @close="showBlockedActionModal = false"
    >
      <p class="text-ink-muted text-sm">
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

    <BaseModal
      :open="settlementToDelete !== null"
      title="Delete this settlement?"
      size="sm"
      data-testid="delete-settlement-confirm"
      @close="settlementToDelete = null"
    >
      <p class="text-ink-muted text-sm">
        Its transfers will disappear and the expenses it covered will become
        editable again. Anything paid against it will need to be re-recorded.
      </p>
      <div class="mt-6 flex justify-end gap-3">
        <AppButton
          variant="secondary"
          size="sm"
          :disabled="deletingSettlement"
          @click="settlementToDelete = null"
        >
          Cancel
        </AppButton>
        <AppButton
          variant="danger"
          size="sm"
          :loading="deletingSettlement"
          loading-label="Deleting…"
          data-testid="confirm-delete-settlement"
          @click="confirmDeleteSettlement"
        >
          Delete
        </AppButton>
      </div>
    </BaseModal>

    <EpcQrModal
      :open="showQrModal"
      :transfer-id="qrTransferId"
      :recipient-name="qrRecipientName"
      :amount="qrAmount"
      @close="showQrModal = false"
    />
  </div>
</template>
