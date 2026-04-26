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
import { formatDateTime } from '@/utils/date'
import { formatAmount } from '@/utils/format'
import { getMemberName } from '@/utils/member'
import AppButton from '@/components/common/AppButton.vue'
import AppBadge from '@/components/common/AppBadge.vue'
import IconButton from '@/components/common/IconButton.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import EpcQrModal from '@/components/expenses/EpcQrModal.vue'
import SettlementMath from '@/components/expenses/SettlementMath.vue'
import type {
  PoolEvent,
  PoolSettlement,
  PoolSettlementTransfer,
} from '@/types/pool'
import {
  can,
  permissionUx,
  type PermissionUx,
} from '@/composables/usePermission'

const props = defineProps<{
  event: PoolEvent
  currentUserId: string | null
}>()

const pool = useObjectPoolStore()
const settlementsStore = useSettlementsStore()

const settlements = computed(() =>
  pool
    .getAll('settlement')
    .filter((s) => s.eventId === props.event.id)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
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

function canDeleteSettlement(settlement: PoolSettlement): boolean {
  return permissionUx(settlement.permissions, 'delete').behavior === 'enabled'
}

function transfersForSettlement(settlementId: string) {
  return pool
    .getAll('settlementTransfer')
    .filter((t) => t.settlementId === settlementId)
}

function activeTransfersForSettlement(settlementId: string) {
  return transfersForSettlement(settlementId).filter((t) => !t.supersededAt)
}

function allTransfersPaid(settlementId: string): boolean {
  const transfers = activeTransfersForSettlement(settlementId)
  return transfers.length > 0 && transfers.every((t) => t.paidAt !== null)
}

function formatDate(iso: string): string {
  return formatDateTime(iso)
}

const showPreviewModal = ref(false)
const settling = ref(false)
const previewMathOpen = ref(false)

const hasTip = computed(() => settlements.value.length > 0)

const paidTransfersInChain = computed(() =>
  settlements.value
    .flatMap((s) => transfersForSettlement(s.id))
    .filter((t) => t.paidAt !== null && !t.supersededAt)
)

const resolveParticipant = (pid: string) => {
  const p = pool.get('expenseParticipant', pid)
  return p ? { userId: p.userId, factor: p.factor } : undefined
}

// Top-up-aware preview: when a tip exists, balances reflect the drift between
// what has already been settled (sum of prior transfers) and what fair shares
// would be right now for every expense in the event. When there's no tip,
// this is just the first-settlement balance over unsettled expenses.
const previewBalances = computed((): Map<string, number> => {
  if (!props.event.startDate || !props.event.endDate) return new Map()
  const attendingRsvps = pool
    .getAll('rsvp')
    .filter((r) => r.eventId === props.event.id && r.attending)
  if (attendingRsvps.length === 0) return new Map()

  if (hasTip.value) {
    const allExpenses = pool
      .getAll('expense')
      .filter((e) => e.eventId === props.event.id)
    if (allExpenses.length === 0) return new Map()
    const currentBalances = computeBalances(
      allExpenses,
      attendingRsvps,
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
    attendingRsvps,
    props.event.startDate,
    props.event.endDate,
    resolveParticipant
  )
})

const previewTransfers = computed((): PreviewTransfer[] => {
  return minimizeTransfers(previewBalances.value)
})

const hasDrift = computed(
  () => hasTip.value && previewTransfers.value.length > 0
)

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

async function deleteSettlement(id: string) {
  await settlementsStore.deleteSettlement(id)
}

const showRecipientOnlyModal = ref(false)

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

const recipientOnlyMessage = ref('')

function markPaidUx(transfer: PoolSettlementTransfer): PermissionUx {
  return permissionUx(transfer.permissions, 'mark_paid')
}

async function handlePaidClick(
  transfer: PoolSettlementTransfer,
  currentlyPaid: boolean
) {
  const ux = markPaidUx(transfer)
  if (ux.behavior === 'modal') {
    recipientOnlyMessage.value = ux.message
    showRecipientOnlyModal.value = true
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
      class="mb-4 rounded-md border-2 border-dashed border-amber-400 bg-amber-50 px-3 py-2 dark:border-amber-600 dark:bg-amber-950/30"
    >
      <p class="text-sm font-medium text-amber-800 dark:text-amber-300">
        The split no longer matches the latest settlement.
      </p>
      <p class="mt-1 text-xs text-amber-700 dark:text-amber-400">
        RSVPs or expenses have changed since it was locked in. Settle the
        difference to bring everyone back to even.
      </p>
    </div>

    <div
      v-if="settlements.length === 0 && !hasExpenses"
      class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-stone-700 dark:bg-stone-800/50"
    >
      <p class="mb-3 text-sm font-medium text-gray-700 dark:text-stone-300">
        How settling up works
      </p>
      <ol class="space-y-3">
        <li class="flex items-start gap-3">
          <span
            class="flex size-6 shrink-0 items-center justify-center rounded-full text-white"
            :class="
              hasExpenses
                ? 'bg-green-500 dark:bg-green-600'
                : 'bg-gray-300 dark:bg-stone-600'
            "
          >
            <CurrencyEuroIcon class="size-3.5" />
          </span>
          <span class="text-sm text-gray-600 dark:text-stone-400">
            <span class="font-medium text-gray-800 dark:text-stone-200"
              >Log expenses</span
            >
            &mdash; everyone adds what they paid for. Costs are split per day
            among attendees.
          </span>
        </li>
        <li class="flex items-start gap-3">
          <span
            class="flex size-6 shrink-0 items-center justify-center rounded-full bg-gray-300 dark:bg-stone-600"
            :class="{
              'bg-green-500 dark:bg-green-600':
                hasExpenses && unsettledExpenseCount > 0,
            }"
          >
            <CalculatorIcon class="size-3.5 text-white" />
          </span>
          <span class="text-sm text-gray-600 dark:text-stone-400">
            <span class="font-medium text-gray-800 dark:text-stone-200"
              >Start settlement</span
            >
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
          <span class="text-sm text-gray-600 dark:text-stone-400">
            <span class="font-medium text-gray-800 dark:text-stone-200"
              >Pay up</span
            >
            &mdash; transfer money via your banking app. When someone you owe
            has added their IBAN in
            <router-link
              to="/profile"
              class="font-medium text-rose-600 hover:text-rose-500 dark:text-rose-400 dark:hover:text-rose-300"
              >their profile</router-link
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
          <span class="text-sm text-gray-600 dark:text-stone-400">
            <span class="font-medium text-gray-800 dark:text-stone-200"
              >Mark paid</span
            >
            &mdash; once the money arrives, the recipient marks the transfer as
            paid so everyone can see what&rsquo;s left.
          </span>
        </li>
      </ol>
    </div>

    <div v-for="settlement in settlements" :key="settlement.id" class="mb-4">
      <div
        class="overflow-hidden rounded-lg border border-gray-200 dark:border-stone-700"
      >
        <div
          class="flex flex-wrap items-center justify-between gap-y-1 border-b border-gray-200 bg-gray-50 px-3 py-2 dark:border-stone-700 dark:bg-stone-800/50"
        >
          <div class="flex min-w-0 items-center gap-2">
            <span class="text-xs text-gray-500 dark:text-stone-400">
              <span v-if="settlement.previousSettlementId">Top-up</span>
              <span v-else>Settled</span>
              by {{ getMemberName(settlement.userId, pool) }} on
              {{ formatDate(settlement.createdAt) }}
            </span>
            <AppBadge v-if="allTransfersPaid(settlement.id)" variant="green">
              <CheckCircleIcon class="size-3" />
              All paid
            </AppBadge>
          </div>
          <IconButton
            v-if="canDeleteSettlement(settlement)"
            variant="danger"
            label="Delete settlement"
            data-testid="delete-settlement-button"
            @click="deleteSettlement(settlement.id)"
          >
            <TrashIcon class="size-4" />
          </IconButton>
        </div>

        <div
          v-if="transfersForSettlement(settlement.id).length > 0"
          class="border-b border-gray-100 px-3 py-1.5 dark:border-stone-700/50"
        >
          <button
            type="button"
            class="flex w-full items-center justify-between rounded-md px-1.5 py-1 text-xs text-gray-600 hover:bg-gray-100 dark:text-stone-400 dark:hover:bg-stone-700/50"
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

        <div class="divide-y divide-gray-100 dark:divide-stone-700/50">
          <div
            v-for="transfer in transfersForSettlement(settlement.id)"
            :key="transfer.id"
            class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 px-4 py-3"
            :class="{
              'opacity-60': transfer.supersededAt,
            }"
          >
            <div class="flex min-w-0 items-center gap-2">
              <span
                class="truncate text-sm text-gray-800 dark:text-stone-200"
                :class="{ 'line-through': transfer.supersededAt }"
              >
                {{ getMemberName(transfer.fromUserId, pool) }}
              </span>
              <span class="shrink-0 text-xs text-gray-400 dark:text-stone-500">
                &rarr;
              </span>
              <span
                class="truncate text-sm text-gray-800 dark:text-stone-200"
                :class="{ 'line-through': transfer.supersededAt }"
              >
                {{ getMemberName(transfer.toUserId, pool) }}
              </span>
              <span
                class="shrink-0 font-mono text-sm font-semibold text-gray-900 dark:text-white"
                :class="{ 'line-through': transfer.supersededAt }"
              >
                {{ formatAmount(transfer.amount) }}
              </span>
              <AppBadge v-if="transfer.supersededAt" variant="gray">
                Superseded
              </AppBadge>
            </div>
            <div v-if="!transfer.supersededAt" class="flex items-center gap-2">
              <button
                v-if="
                  !transfer.paidAt && can(transfer.permissions, 'generate_qr')
                "
                type="button"
                class="inline-flex cursor-pointer items-center gap-1.5 rounded-md bg-amber-600 px-2.5 py-1.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-500 dark:bg-amber-600 dark:hover:bg-amber-500"
                title="Show QR code for bank transfer"
                @click="openQrModal(transfer)"
              >
                <QrCodeIcon class="size-4" aria-hidden="true" />
                Pay via QR
              </button>
              <button
                type="button"
                class="cursor-pointer rounded-md px-3 py-1.5 text-sm font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
                :class="
                  transfer.paidAt
                    ? 'bg-green-100 text-green-700 hover:bg-green-200 focus-visible:outline-green-500 dark:bg-green-900/30 dark:text-green-400 dark:hover:bg-green-900/50'
                    : 'bg-cyan-600 text-white shadow-sm hover:bg-cyan-700 focus-visible:outline-cyan-600 dark:bg-cyan-700 dark:hover:bg-cyan-600'
                "
                @click="handlePaidClick(transfer, !!transfer.paidAt)"
              >
                {{ transfer.paidAt ? 'Paid' : 'Mark as paid' }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <BaseModal
      v-if="showPreviewModal"
      :open="showPreviewModal"
      :title="hasTip ? 'Top-up Preview' : 'Settlement Preview'"
      size="md"
      @close="showPreviewModal = false"
    >
      <div
        class="mb-4 rounded-md border-2 border-dashed border-amber-400 bg-amber-50 px-3 py-2 dark:border-amber-600 dark:bg-amber-950/30"
      >
        <p class="text-sm font-medium text-amber-800 dark:text-amber-300">
          This is a preview &mdash; nothing has been settled yet.
        </p>
      </div>

      <p
        v-if="unsettledExpenseCount > 0"
        class="mb-3 text-sm text-gray-600 dark:text-stone-400"
      >
        {{ unsettledExpenseCount }}
        expense{{ unsettledExpenseCount === 1 ? '' : 's' }} will be locked to
        this settlement.
      </p>
      <p
        v-else-if="hasTip"
        class="mb-3 text-sm text-gray-600 dark:text-stone-400"
      >
        This top-up covers the drift since the last settlement — no new expenses
        are being locked.
      </p>

      <div v-if="previewTransfers.length > 0" class="mb-3">
        <button
          type="button"
          class="flex w-full items-center justify-between rounded-md px-2 py-1 text-sm text-gray-600 hover:bg-gray-100 dark:text-stone-400 dark:hover:bg-stone-700/50"
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
        class="overflow-hidden rounded-lg border border-dashed border-gray-300 dark:border-stone-600"
      >
        <div class="divide-y divide-gray-100 dark:divide-stone-700/50">
          <div
            v-for="(transfer, i) in previewTransfers"
            :key="i"
            class="flex items-center gap-2 px-3 py-2"
          >
            <span class="truncate text-sm text-gray-800 dark:text-stone-200">
              {{ getMemberName(transfer.fromUserId, pool) }}
            </span>
            <span class="shrink-0 text-xs text-gray-400 dark:text-stone-500">
              &rarr;
            </span>
            <span class="truncate text-sm text-gray-800 dark:text-stone-200">
              {{ getMemberName(transfer.toUserId, pool) }}
            </span>
            <span
              class="ml-auto shrink-0 font-mono text-sm font-medium text-gray-900 dark:text-white"
            >
              {{ formatAmount(transfer.amount) }}
            </span>
          </div>
        </div>
      </div>

      <p
        v-else-if="previewTransfers.length === 0"
        class="text-sm text-gray-500 dark:text-stone-400"
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
      :open="showRecipientOnlyModal"
      title="Can't mark as paid"
      size="sm"
      @close="showRecipientOnlyModal = false"
    >
      <p class="text-sm text-gray-600 dark:text-stone-400">
        {{ recipientOnlyMessage }}
      </p>
      <div class="mt-6 flex justify-end">
        <AppButton
          variant="secondary"
          size="sm"
          @click="showRecipientOnlyModal = false"
        >
          OK
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
