<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  BanknotesIcon,
  CalculatorIcon,
  CheckCircleIcon,
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
  minimizeTransfers,
  type PreviewTransfer,
} from '@/utils/settlement'
import { formatDateTime } from '@/utils/date'
import { formatAmount } from '@/utils/format'
import { getMemberName } from '@/utils/member'
import AppButton from '@/components/common/AppButton.vue'
import AppBadge from '@/components/common/AppBadge.vue'
import IconButton from '@/components/common/IconButton.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import EpcQrModal from '@/components/expenses/EpcQrModal.vue'
import type {
  PoolEvent,
  PoolSettlement,
  PoolSettlementTransfer,
} from '@/types/pool'
import { permissionUx, type PermissionUx } from '@/composables/usePermission'

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

function allTransfersPaid(settlementId: string): boolean {
  const transfers = transfersForSettlement(settlementId)
  return transfers.length > 0 && transfers.every((t) => t.paidAt !== null)
}

function formatDate(iso: string): string {
  return formatDateTime(iso)
}

const showPreviewModal = ref(false)
const settling = ref(false)

const previewTransfers = computed((): PreviewTransfer[] => {
  if (!props.event.startDate || !props.event.endDate) return []

  const unsettledExpenses = pool
    .getAll('expense')
    .filter((e) => e.eventId === props.event.id && !e.settlementId)

  const attendingRsvps = pool
    .getAll('rsvp')
    .filter((r) => r.eventId === props.event.id && r.attending)

  if (unsettledExpenses.length === 0 || attendingRsvps.length === 0) return []

  const resolveParticipantUserId = (pid: string) =>
    pool.get('expenseParticipant', pid)?.userId

  const balances = computeBalances(
    unsettledExpenses,
    attendingRsvps,
    props.event.startDate,
    props.event.endDate,
    resolveParticipantUserId
  )
  return minimizeTransfers(balances)
})

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

function memberHasIban(userId: string | null): boolean {
  if (!userId) return false
  return pool.findBy('member', 'userId', userId)?.hasIban ?? false
}

function openQrModal(transfer: {
  id: string
  toUserId: string | null
  amount: number
}) {
  if (!transfer.toUserId) return
  const member = pool.findBy('member', 'userId', transfer.toUserId)
  if (!member?.hasIban) return
  qrTransferId.value = transfer.id
  qrRecipientName.value = member.name ?? member.email
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
  <div v-if="event.startDate && event.endDate" class="mt-8">
    <div class="mb-4 flex items-center justify-between">
      <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
        Settlements
      </h2>
      <AppButton
        v-if="unsettledExpenseCount > 0"
        data-testid="start-settlement-button"
        @click="openPreview"
      >
        <ScaleIcon class="size-4" />
        Start settlement
        <span class="text-rose-200">({{ unsettledExpenseCount }})</span>
      </AppButton>
    </div>

    <div
      v-if="settlements.length === 0"
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
              Settled by {{ getMemberName(settlement.userId, pool) }} on
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

        <div class="divide-y divide-gray-100 dark:divide-stone-700/50">
          <div
            v-for="transfer in transfersForSettlement(settlement.id)"
            :key="transfer.id"
            class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 px-4 py-3"
          >
            <div class="flex min-w-0 items-center gap-2">
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
                class="shrink-0 font-mono text-sm font-semibold text-gray-900 dark:text-white"
              >
                {{ formatAmount(transfer.amount) }}
              </span>
            </div>
            <div class="flex items-center gap-2">
              <button
                v-if="
                  !transfer.paidAt &&
                  transfer.fromUserId === currentUserId &&
                  memberHasIban(transfer.toUserId)
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
                {{ transfer.paidAt ? 'Paid' : 'Mark paid' }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <BaseModal
      v-if="showPreviewModal"
      :open="showPreviewModal"
      title="Settlement Preview"
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

      <p class="mb-3 text-sm text-gray-600 dark:text-stone-400">
        {{ unsettledExpenseCount }}
        expense{{ unsettledExpenseCount === 1 ? '' : 's' }} will be locked to
        this settlement.
      </p>

      <div
        v-if="previewTransfers.length > 0"
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

      <p v-else class="text-sm text-gray-500 dark:text-stone-400">
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
