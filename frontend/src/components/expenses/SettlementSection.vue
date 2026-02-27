<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  CheckCircleIcon,
  EyeIcon,
  LockClosedIcon,
  TrashIcon,
} from '@heroicons/vue/24/outline'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useSettlementsStore } from '@/stores/settlements'
import {
  computeBalances,
  minimizeTransfers,
  type PreviewTransfer,
} from '@/utils/settlement'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import type { PoolEvent } from '@/types/pool'

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

function getMemberName(userId: string | null): string {
  if (!userId) return 'Unknown'
  const member = pool.findBy('member', 'userId', userId)
  return member?.name ?? member?.email ?? 'Unknown'
}

function canDeleteSettlement(settlementUserId: string | null): boolean {
  if (!props.currentUserId) return false
  if (settlementUserId === props.currentUserId) return true
  if (props.event.userId === props.currentUserId) return true
  return false
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

function formatAmount(amount: number): string {
  return `€${amount.toFixed(2)}`
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
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

  const balances = computeBalances(
    unsettledExpenses,
    attendingRsvps,
    props.event.startDate,
    props.event.endDate
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

function canMarkPaid(toUserId: string | null): boolean {
  return props.currentUserId !== null && toUserId === props.currentUserId
}

async function handlePaidClick(
  transferId: string,
  currentlyPaid: boolean,
  toUserId: string | null
) {
  if (!canMarkPaid(toUserId)) {
    showRecipientOnlyModal.value = true
    return
  }
  await settlementsStore.markTransferPaid(transferId, !currentlyPaid)
}
</script>

<template>
  <div v-if="event.startDate && event.endDate" class="mt-8">
    <div class="mb-4 flex items-center justify-between">
      <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
        Settlements
      </h2>
      <AppButton v-if="unsettledExpenseCount > 0" @click="openPreview">
        <EyeIcon class="size-4" />
        Preview settlement
        <span class="text-rose-200">({{ unsettledExpenseCount }})</span>
      </AppButton>
    </div>

    <p
      v-if="settlements.length === 0 && hasExpenses"
      class="text-sm text-gray-500 dark:text-stone-400"
    >
      No settlements yet. Settle up to lock expenses and compute transfers.
    </p>
    <p
      v-else-if="settlements.length === 0"
      class="text-sm text-gray-500 dark:text-stone-400"
    >
      Add expenses first, then settle up.
    </p>

    <div v-for="settlement in settlements" :key="settlement.id" class="mb-4">
      <div
        class="overflow-hidden rounded-lg border border-gray-200 dark:border-stone-700"
      >
        <div
          class="flex flex-wrap items-center justify-between gap-y-1 border-b border-gray-200 bg-gray-50 px-3 py-2 dark:border-stone-700 dark:bg-stone-800/50"
        >
          <div class="flex min-w-0 items-center gap-2">
            <span class="text-xs text-gray-500 dark:text-stone-400">
              Settled by {{ getMemberName(settlement.userId) }} on
              {{ formatDate(settlement.createdAt) }}
            </span>
            <span
              v-if="allTransfersPaid(settlement.id)"
              class="inline-flex items-center gap-1 rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700 dark:bg-green-900/30 dark:text-green-400"
            >
              <CheckCircleIcon class="size-3" />
              All paid
            </span>
          </div>
          <IconButton
            v-if="canDeleteSettlement(settlement.userId)"
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
            class="flex flex-wrap items-center justify-between gap-y-1 px-3 py-2"
          >
            <div class="flex min-w-0 items-center gap-2">
              <span class="truncate text-sm text-gray-800 dark:text-stone-200">
                {{ getMemberName(transfer.fromUserId) }}
              </span>
              <span class="shrink-0 text-xs text-gray-400 dark:text-stone-500">
                &rarr;
              </span>
              <span class="truncate text-sm text-gray-800 dark:text-stone-200">
                {{ getMemberName(transfer.toUserId) }}
              </span>
              <span
                class="shrink-0 font-mono text-sm font-medium text-gray-900 dark:text-white"
              >
                {{ formatAmount(transfer.amount) }}
              </span>
            </div>
            <button
              type="button"
              class="rounded-md px-2 py-1 text-xs font-medium transition-colors"
              :class="
                transfer.paidAt
                  ? 'bg-green-100 text-green-700 hover:bg-green-200 dark:bg-green-900/30 dark:text-green-400 dark:hover:bg-green-900/50'
                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-stone-600'
              "
              @click="
                handlePaidClick(
                  transfer.id,
                  !!transfer.paidAt,
                  transfer.toUserId
                )
              "
            >
              {{ transfer.paidAt ? 'Paid' : 'Mark paid' }}
            </button>
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
              {{ getMemberName(transfer.fromUserId) }}
            </span>
            <span class="shrink-0 text-xs text-gray-400 dark:text-stone-500">
              &rarr;
            </span>
            <span class="truncate text-sm text-gray-800 dark:text-stone-200">
              {{ getMemberName(transfer.toUserId) }}
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

      <div class="mt-5 flex justify-end gap-3">
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
        Only the person receiving the money can mark a transfer as paid.
      </p>
      <div class="mt-4 flex justify-end">
        <AppButton
          variant="secondary"
          size="sm"
          @click="showRecipientOnlyModal = false"
        >
          OK
        </AppButton>
      </div>
    </BaseModal>
  </div>
</template>
