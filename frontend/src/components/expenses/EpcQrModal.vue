<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue'
import { CheckIcon, ClipboardIcon } from '@heroicons/vue/24/outline'
import { CheckCircleIcon } from '@heroicons/vue/24/solid'
import BaseModal from '@/components/common/BaseModal.vue'
// Bypasses the pool: payment details are sender-authorised, per-transfer,
// and short-lived. They must not be cached in the shared object pool where
// other clients (or a later session) could pick them up.
import { rawApi, type ApiError } from '@/api/client'
import { useSettlementsStore } from '@/stores/settlements'

// The modal works in two modes:
//   - transferId: per-event payment for a single SettlementTransfer
//   - netRequest: workspace-level net payment across multiple transfers
// Exactly one should be non-null when open.
interface NetRequest {
  workspaceId: string
  counterpartyUserId: string
  expectedAmount: number
  // Snapshot of contributing transfer ids at modal-open time. Used for
  // optimistic UI updates when the sender attests; server is still
  // authoritative on which rows actually get paid_at.
  underlyingTransferIds: string[]
}

const props = defineProps<{
  open: boolean
  transferId?: string | null
  netRequest?: NetRequest | null
  recipientName: string | null
  amount: number | null
}>()

defineEmits<{
  close: []
}>()

interface PaymentDetails {
  recipientName: string
  amount: number
  reference: string
  iban: string | null
  qrPng: string | null
}

const details = ref<PaymentDetails | null>(null)
const detailsError = ref(false)
const driftError = ref(false)
const loading = ref(false)
const copied = ref(false)
const copyError = ref(false)
const attestState = ref<'idle' | 'submitting' | 'success' | 'error'>('idle')
const attestErrorMessage = ref<string | null>(null)
const settlementsStore = useSettlementsStore()
let copiedTimer: ReturnType<typeof setTimeout> | null = null
// Per-open token: every open bumps it. A response or timeout that resolves
// after a subsequent open (even for the same transferId) is then ignored.
let fetchToken = 0

function isApiError(e: unknown): e is ApiError {
  return (
    typeof e === 'object' &&
    e !== null &&
    'status' in e &&
    typeof (e as { status: unknown }).status === 'number'
  )
}

function clearCopiedTimer() {
  if (copiedTimer) {
    clearTimeout(copiedTimer)
    copiedTimer = null
  }
}

function buildPaymentDetailsPath(): string | null {
  // Both modes set is a caller bug — callers should pick one. Fail loud in
  // dev so it's caught before shipping a wrong-amount QR; in prod we still
  // pick `transferId` (more specific) over `netRequest` deterministically.
  if (props.transferId && props.netRequest && import.meta.env.DEV) {
    console.warn(
      '[EpcQrModal] both transferId and netRequest provided; using transferId'
    )
  }
  if (props.transferId) {
    return `/settlements/transfers/${props.transferId}/payment-details`
  }
  if (props.netRequest) {
    const { workspaceId, counterpartyUserId, expectedAmount } = props.netRequest
    const params = new URLSearchParams({
      workspace_id: workspaceId,
      counterparty: counterpartyUserId,
      expected_amount: String(expectedAmount),
    })
    return `/settlements/net-transfers/payment-details?${params.toString()}`
  }
  return null
}

watch(
  () => props.open,
  async (isOpen) => {
    clearCopiedTimer()
    // Bump on every transition so any in-flight request from the previous
    // open is invalidated — including when the modal closes.
    const token = ++fetchToken
    const path = buildPaymentDetailsPath()
    if (!isOpen || !path) {
      details.value = null
      detailsError.value = false
      driftError.value = false
      loading.value = false
      copied.value = false
      attestState.value = 'idle'
      attestErrorMessage.value = null
      return
    }
    detailsError.value = false
    driftError.value = false
    details.value = null
    copied.value = false
    copyError.value = false
    attestState.value = 'idle'
    attestErrorMessage.value = null
    loading.value = true
    try {
      const response = await rawApi.get<PaymentDetails>(path)
      if (token === fetchToken) {
        details.value = response.data
      }
    } catch (e) {
      if (token !== fetchToken) return
      // 409 on the net-payment endpoint is the drift signal — the live net
      // no longer matches what the caller saw. Surface it specifically so
      // the user knows to refresh, instead of the generic "couldn't load".
      if (isApiError(e) && e.status === 409) {
        driftError.value = true
      } else {
        detailsError.value = true
      }
    } finally {
      if (token === fetchToken) {
        loading.value = false
      }
    }
  }
)

onBeforeUnmount(clearCopiedTimer)

async function attestPaid() {
  if (attestState.value === 'submitting') return
  attestState.value = 'submitting'
  attestErrorMessage.value = null
  try {
    if (props.transferId) {
      await settlementsStore.markTransferPaid(props.transferId, true)
    } else if (props.netRequest) {
      await settlementsStore.markNetPaid({
        workspaceId: props.netRequest.workspaceId,
        counterpartyUserId: props.netRequest.counterpartyUserId,
        expectedAmount: props.netRequest.expectedAmount,
        underlyingTransferIds: props.netRequest.underlyingTransferIds,
      })
    }
    attestState.value = 'success'
  } catch (e) {
    attestState.value = 'error'
    if (isApiError(e) && e.status === 409) {
      attestErrorMessage.value =
        'Balance changed since this dialog opened. Close and refresh before marking paid.'
    } else if (isApiError(e)) {
      attestErrorMessage.value = e.message
    } else {
      attestErrorMessage.value = 'Could not mark as paid. Please try again.'
    }
  }
}

async function copyIban() {
  if (!details.value?.iban) return
  const plainIban = details.value.iban.replace(/\s/g, '')
  try {
    await navigator.clipboard.writeText(plainIban)
    copied.value = true
    copyError.value = false
  } catch {
    // Insecure-context, denied permission, or no clipboard API (rare).
    copyError.value = true
    copied.value = false
    return
  }
  clearCopiedTimer()
  copiedTimer = setTimeout(() => {
    copied.value = false
    copiedTimer = null
  }, 2000)
}
</script>

<template>
  <BaseModal
    :open="open"
    title="Pay via bank transfer"
    size="sm"
    @close="$emit('close')"
  >
    <div v-if="transferId || netRequest" class="space-y-4">
      <dl class="space-y-2 text-sm">
        <div class="flex justify-between">
          <dt class="text-gray-500 dark:text-stone-400">To</dt>
          <dd class="font-medium text-gray-900 dark:text-white">
            {{ recipientName }}
          </dd>
        </div>
        <div class="flex justify-between">
          <dt class="text-gray-500 dark:text-stone-400">Amount</dt>
          <dd class="font-mono font-medium text-gray-900 dark:text-white">
            &euro;{{ amount?.toFixed(2) }}
          </dd>
        </div>
      </dl>

      <Transition
        mode="out-in"
        enter-active-class="transition-opacity duration-150 ease-out"
        leave-active-class="transition-opacity duration-100 ease-in"
        enter-from-class="opacity-0"
        enter-to-class="opacity-100"
        leave-from-class="opacity-100"
        leave-to-class="opacity-0"
      >
        <div
          v-if="loading"
          key="loading"
          class="flex justify-center py-8"
          role="status"
          aria-live="polite"
        >
          <span
            class="inline-block size-8 animate-spin rounded-full border-2 border-gray-300 border-t-cyan-600 dark:border-stone-600 dark:border-t-cyan-400"
            aria-hidden="true"
          />
          <span class="sr-only">Loading payment details</span>
        </div>

        <div
          v-else-if="driftError"
          key="drift"
          data-testid="payment-drift"
          class="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-700 dark:bg-amber-950/30 dark:text-amber-300"
        >
          <p class="font-medium">
            The balance has changed since this page loaded.
          </p>
          <p class="mt-1 text-amber-700 dark:text-amber-400">
            Close this dialog and refresh the page to see the up-to-date amount
            before paying.
          </p>
        </div>

        <p
          v-else-if="detailsError"
          key="error"
          class="text-center text-sm text-red-600 dark:text-red-400"
        >
          Could not load payment details.
        </p>

        <div
          v-else-if="attestState === 'success'"
          key="success"
          data-testid="attest-success"
          class="flex flex-col items-center gap-3 py-6 text-center"
        >
          <CheckCircleIcon
            class="size-12 text-emerald-500 dark:text-emerald-400"
            aria-hidden="true"
          />
          <p class="text-base font-medium text-gray-900 dark:text-white">
            Marked as paid.
          </p>
          <p class="text-sm text-gray-500 dark:text-stone-400">
            {{ recipientName }} will see this update next time they open
            Tayaway.
          </p>
          <button
            type="button"
            class="mt-2 cursor-pointer rounded-md bg-cyan-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm hover:bg-cyan-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-cyan-600 dark:bg-cyan-700 dark:hover:bg-cyan-600"
            @click="$emit('close')"
          >
            Done
          </button>
        </div>

        <div v-else-if="details" key="details" class="space-y-4">
          <div
            v-if="!details.iban"
            data-testid="recipient-no-iban"
            class="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-700 dark:bg-amber-950/30 dark:text-amber-300"
          >
            <p class="font-medium">No IBAN on file for {{ recipientName }}.</p>
            <p class="mt-1 text-amber-700 dark:text-amber-400">
              Ask them to add it on their profile page so the QR code and
              copy-paste IBAN can show up here. In the meantime, settle up with
              a payment request &mdash; a Tikkie, a PayPal link, or whatever the
              two of you usually use.
            </p>
          </div>

          <template v-else>
            <div
              v-if="details.qrPng"
              class="flex flex-col items-center gap-2 rounded-lg bg-white p-4"
            >
              <img
                :src="`data:image/png;base64,${details.qrPng}`"
                alt="EPC QR code for bank transfer"
                class="size-48"
              />
            </div>

            <p
              v-else
              class="text-center text-sm text-gray-500 dark:text-stone-400"
            >
              QR code unavailable for this transfer &mdash; copy the IBAN below
              to pay manually.
            </p>

            <p
              v-if="details.qrPng"
              class="text-center text-xs text-gray-500 dark:text-stone-400"
            >
              Scan with your banking app to pre-fill the transfer, or copy the
              IBAN below to pay manually.
            </p>

            <div class="space-y-1">
              <label
                for="payment-iban"
                class="block text-xs text-gray-500 dark:text-stone-400"
              >
                IBAN
              </label>
              <div class="flex items-stretch gap-2">
                <input
                  id="payment-iban"
                  data-testid="payment-iban"
                  :value="details.iban"
                  readonly
                  class="min-w-0 flex-1 rounded-md border border-gray-300 bg-gray-50 px-2.5 py-1.5 font-mono text-sm text-gray-900 select-all focus:outline-none dark:border-stone-600 dark:bg-stone-800 dark:text-white"
                  @focus="($event.target as HTMLInputElement).select()"
                />
                <button
                  type="button"
                  class="inline-flex shrink-0 cursor-pointer items-center gap-1.5 rounded-md bg-cyan-600 px-2.5 py-1.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-cyan-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-cyan-600 dark:bg-cyan-700 dark:hover:bg-cyan-600"
                  :aria-label="copied ? 'IBAN copied' : 'Copy IBAN'"
                  @click="copyIban"
                >
                  <CheckIcon v-if="copied" class="size-4" aria-hidden="true" />
                  <ClipboardIcon v-else class="size-4" aria-hidden="true" />
                  {{ copied ? 'Copied' : 'Copy' }}
                </button>
              </div>
              <p
                v-if="copyError"
                class="text-xs text-red-600 dark:text-red-400"
              >
                Couldn&rsquo;t copy &mdash; select the IBAN and copy it
                manually.
              </p>
            </div>
          </template>

          <div class="border-t border-gray-200 pt-4 dark:border-stone-700">
            <button
              type="button"
              data-testid="attest-paid"
              :disabled="attestState === 'submitting'"
              class="inline-flex w-full cursor-pointer items-center justify-center gap-1.5 rounded-md bg-emerald-600 px-3 py-2 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-emerald-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-emerald-700 dark:hover:bg-emerald-600"
              @click="attestPaid"
            >
              <CheckIcon class="size-4" aria-hidden="true" />
              {{
                attestState === 'submitting'
                  ? 'Marking…'
                  : "I've paid — mark as paid"
              }}
            </button>
            <p
              class="mt-2 text-center text-xs text-gray-500 dark:text-stone-400"
            >
              Click after you've completed the bank transfer.
              {{ recipientName }}
              can flip this back if it didn't actually arrive.
            </p>
            <p
              v-if="attestState === 'error' && attestErrorMessage"
              data-testid="attest-error"
              class="mt-2 text-center text-xs text-red-600 dark:text-red-400"
            >
              {{ attestErrorMessage }}
            </p>
          </div>
        </div>
      </Transition>
    </div>
  </BaseModal>
</template>
