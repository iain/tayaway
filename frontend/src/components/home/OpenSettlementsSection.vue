<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  BanknotesIcon,
  QrCodeIcon,
  ScaleIcon,
} from '@heroicons/vue/24/outline'
import { useObjectPoolStore } from '@/stores'
import { useSettlementsStore } from '@/stores/settlements'
import { getMemberName } from '@/utils/member'
import LedgerAmount from '@/components/common/LedgerAmount.vue'
import AppButton from '@/components/common/AppButton.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import AlertBox from '@/components/common/AlertBox.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
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
    <SectionHeading :icon="ScaleIcon" title="Open settlements" />
    <p class="text-ink-muted mb-4 -mt-2 text-sm">
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
        class="mt-1 cursor-pointer text-sm font-medium text-amber-700 underline transition-colors hover:text-amber-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus dark:text-amber-400 dark:hover:text-amber-200"
        @click="router.push('/settings/payment')"
      >
        Add IBAN in settings
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
            <p class="text-ink text-sm">
              <span class="font-semibold">{{
                getMemberName(transfer.fromUserId, pool)
              }}</span>
              owes you
              <span class="text-ink font-semibold">
                <LedgerAmount :amount="transfer.amount" />
              </span>
            </p>
            <p class="text-ink-muted mt-0.5 text-xs">
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
          <AppButton
            variant="inflow"
            size="sm"
            class="min-h-[44px] sm:min-h-0"
            :loading="markingPaidIds.has(transfer.id)"
            loading-label="Marking..."
            @click="handleMarkPaid(transfer.id)"
          >
            Mark as received
          </AppButton>
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
            <p class="text-ink text-sm">
              You owe
              <span class="text-ink font-semibold">{{
                getMemberName(transfer.toUserId, pool)
              }}</span>
            </p>
            <p class="text-ink mt-0.5 text-lg font-bold">
              <LedgerAmount :amount="transfer.amount" />
            </p>
            <p class="text-ink-muted mt-0.5 text-xs">
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
          <AppButton
            variant="outflow"
            size="sm"
            class="min-h-[44px] sm:min-h-0"
            title="Show QR code for bank transfer"
            @click="openQrModal(transfer)"
          >
            <QrCodeIcon class="size-4" aria-hidden="true" />
            Pay via QR
          </AppButton>
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
