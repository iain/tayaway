<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { BanknotesIcon, QrCodeIcon } from '@heroicons/vue/24/outline'
import { useObjectPoolStore } from '@/stores'
import { useSettlementsStore } from '@/stores/settlements'
import { getMemberName } from '@/utils/member'
import { formatAmount } from '@/utils/format'
import BaseCard from '@/components/common/BaseCard.vue'
import AlertBox from '@/components/common/AlertBox.vue'
import EpcQrModal from '@/components/expenses/EpcQrModal.vue'
import type { PoolSettlementTransfer } from '@/types/pool'

defineProps<{
  transfersOwedToYou: PoolSettlementTransfer[]
  transfersYouOwe: PoolSettlementTransfer[]
  hasIban: boolean
}>()

const router = useRouter()
const pool = useObjectPoolStore()
const settlementsStore = useSettlementsStore()

const markingPaidIds = ref(new Set<string>())

async function handleMarkPaid(transferId: string) {
  if (markingPaidIds.value.has(transferId)) return
  markingPaidIds.value.add(transferId)
  try {
    await settlementsStore.markTransferPaid(transferId, true)
  } finally {
    markingPaidIds.value.delete(transferId)
  }
}

const showQrModal = ref(false)
const qrTransferId = ref<string | null>(null)
const qrRecipientName = ref<string | null>(null)
const qrAmount = ref<number | null>(null)

function openQrModal(transfer: PoolSettlementTransfer) {
  if (!transfer.toUserId) return
  const member = pool.findBy('member', 'userId', transfer.toUserId)
  qrTransferId.value = transfer.id
  qrRecipientName.value = member?.name ?? member?.email ?? null
  qrAmount.value = transfer.amount
  showQrModal.value = true
}

function getEventNameForTransfer(transfer: PoolSettlementTransfer): string {
  const settlement = pool.get('settlement', transfer.settlementId)
  if (!settlement) return 'Unknown event'
  const event = pool.get('event', settlement.eventId)
  return event?.name ?? 'Unknown event'
}

function getEventIdForTransfer(
  transfer: PoolSettlementTransfer
): string | null {
  const settlement = pool.get('settlement', transfer.settlementId)
  if (!settlement) return null
  return settlement.eventId
}
</script>

<template>
  <section>
    <h2 class="mb-1 text-lg font-semibold text-gray-900 dark:text-white">
      Open settlements
    </h2>
    <p class="mb-4 text-sm text-gray-500 dark:text-stone-400">
      Mark a transfer as paid once you've received the payment.
    </p>

    <AlertBox
      v-if="transfersOwedToYou.length > 0 && !hasIban"
      variant="warning"
      :icon="BanknotesIcon"
      class="mb-3"
    >
      <p class="text-sm">
        Add your IBAN so others can pay you with a single QR code scan.
      </p>
      <button
        type="button"
        class="mt-1 text-sm font-medium text-amber-700 underline hover:text-amber-900 dark:text-amber-400 dark:hover:text-amber-200"
        @click="router.push('/profile')"
      >
        Add IBAN in profile
      </button>
    </AlertBox>

    <ul class="space-y-3">
      <BaseCard
        v-for="transfer in transfersOwedToYou"
        :key="transfer.id"
        as="li"
        class="overflow-hidden"
      >
        <div
          class="flex flex-wrap items-center justify-between gap-y-2 px-4 py-3 sm:px-6"
        >
          <div class="min-w-0 flex-1">
            <p class="text-sm text-gray-900 dark:text-white">
              <span class="font-semibold">{{
                getMemberName(transfer.fromUserId, pool)
              }}</span>
              owes you
              <span
                class="font-mono font-semibold text-gray-900 dark:text-white"
                >{{ formatAmount(transfer.amount) }}</span
              >
            </p>
            <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
              <router-link
                v-if="getEventIdForTransfer(transfer)"
                :to="`/events/${getEventIdForTransfer(transfer)}/expenses`"
                class="hover:text-rose-600 hover:underline dark:hover:text-rose-400"
              >
                {{ getEventNameForTransfer(transfer) }}
              </router-link>
              <span v-else>{{ getEventNameForTransfer(transfer) }}</span>
            </p>
          </div>
          <button
            type="button"
            :disabled="markingPaidIds.has(transfer.id)"
            class="cursor-pointer rounded-md bg-cyan-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-cyan-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-cyan-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-cyan-700 dark:hover:bg-cyan-600"
            @click="handleMarkPaid(transfer.id)"
          >
            {{
              markingPaidIds.has(transfer.id) ? 'Marking...' : 'Mark as paid'
            }}
          </button>
        </div>
      </BaseCard>
      <BaseCard
        v-for="transfer in transfersYouOwe"
        :key="transfer.id"
        as="li"
        variant="action"
        class="overflow-hidden"
      >
        <div
          class="flex flex-wrap items-center justify-between gap-y-2 px-4 py-3 sm:px-6"
        >
          <div class="min-w-0 flex-1">
            <p class="text-sm text-gray-700 dark:text-stone-300">
              You owe
              <span class="font-semibold text-gray-900 dark:text-white">{{
                getMemberName(transfer.toUserId, pool)
              }}</span>
            </p>
            <p
              class="mt-0.5 font-mono text-lg font-bold text-amber-700 dark:text-amber-400"
            >
              {{ formatAmount(transfer.amount) }}
            </p>
            <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
              <router-link
                v-if="getEventIdForTransfer(transfer)"
                :to="`/events/${getEventIdForTransfer(transfer)}/expenses`"
                class="hover:text-rose-600 hover:underline dark:hover:text-rose-400"
              >
                {{ getEventNameForTransfer(transfer) }}
              </router-link>
              <span v-else>{{ getEventNameForTransfer(transfer) }}</span>
            </p>
          </div>
          <button
            type="button"
            class="inline-flex cursor-pointer items-center gap-1.5 rounded-md bg-amber-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-500 dark:bg-amber-600 dark:hover:bg-amber-500"
            title="Show QR code for bank transfer"
            @click="openQrModal(transfer)"
          >
            <QrCodeIcon class="size-4" aria-hidden="true" />
            Pay via QR
          </button>
        </div>
      </BaseCard>
    </ul>

    <EpcQrModal
      :open="showQrModal"
      :transfer-id="qrTransferId"
      :recipient-name="qrRecipientName"
      :amount="qrAmount"
      @close="showQrModal = false"
    />
  </section>
</template>
