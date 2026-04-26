<script setup lang="ts">
import { ref, watch } from 'vue'
import { CheckIcon, ClipboardIcon } from '@heroicons/vue/24/outline'
import BaseModal from '@/components/common/BaseModal.vue'
// Bypasses the pool: payment details are sender-authorised, per-transfer,
// and short-lived. They must not be cached in the shared object pool where
// other clients (or a later session) could pick them up.
import { rawApi } from '@/api/client'

const props = defineProps<{
  open: boolean
  transferId: string | null
  recipientName: string | null
  amount: number | null
  recipientHasIban: boolean
}>()

defineEmits<{
  close: []
}>()

interface PaymentDetails {
  recipientName: string
  iban: string
  amount: number
  reference: string
}

const imgSrc = ref<string | null>(null)
const imgError = ref(false)
const details = ref<PaymentDetails | null>(null)
const detailsError = ref(false)
const copied = ref(false)
const copyError = ref(false)
let copiedTimer: ReturnType<typeof setTimeout> | null = null

watch(
  () => props.open,
  async (isOpen) => {
    if (!isOpen || !props.transferId) {
      details.value = null
      imgSrc.value = null
      copied.value = false
      return
    }
    imgError.value = false
    detailsError.value = false
    details.value = null
    copied.value = false
    copyError.value = false
    if (!props.recipientHasIban) {
      // Skip the fetches — both the QR and payment-details endpoints would
      // 422 on a missing IBAN. The template renders the explanatory state.
      imgSrc.value = null
      return
    }
    imgSrc.value = `/api/settlements/transfers/${props.transferId}/qr`
    const transferId = props.transferId
    try {
      const response = await rawApi.get<PaymentDetails>(
        `/settlements/transfers/${transferId}/payment-details`
      )
      if (props.transferId === transferId) {
        details.value = response.data
      }
    } catch {
      detailsError.value = true
    }
  }
)

async function copyIban() {
  if (!details.value) return
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
  if (copiedTimer) clearTimeout(copiedTimer)
  copiedTimer = setTimeout(() => {
    copied.value = false
  }, 2000)
}

function handleImgError() {
  imgError.value = true
  imgSrc.value = null
}
</script>

<template>
  <BaseModal
    :open="open"
    title="Pay via bank transfer"
    size="sm"
    @close="$emit('close')"
  >
    <div v-if="transferId" class="space-y-4">
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

      <div
        v-if="!recipientHasIban"
        data-testid="recipient-no-iban"
        class="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-700 dark:bg-amber-950/30 dark:text-amber-300"
      >
        <p class="font-medium">No IBAN on file for {{ recipientName }}.</p>
        <p class="mt-1 text-amber-700 dark:text-amber-400">
          Ask them to add it on their profile page so the QR code and copy-paste
          IBAN can show up here. In the meantime, settle up with a payment
          request &mdash; a Tikkie, a PayPal link, or whatever the two of you
          usually use.
        </p>
      </div>

      <template v-else>
        <div
          v-if="imgSrc && !imgError"
          class="flex flex-col items-center gap-2 rounded-lg bg-white p-4"
        >
          <img
            :src="imgSrc"
            alt="EPC QR code for bank transfer"
            class="size-48"
            @error="handleImgError"
          />
        </div>

        <p
          v-if="imgError"
          class="text-center text-sm text-red-600 dark:text-red-400"
        >
          Could not generate QR code.
        </p>

        <p class="text-center text-xs text-gray-500 dark:text-stone-400">
          Scan with your banking app to pre-fill the transfer, or copy the IBAN
          below to pay manually.
        </p>
      </template>

      <div v-if="details" class="space-y-1">
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
        <p v-if="copyError" class="text-xs text-red-600 dark:text-red-400">
          Couldn&rsquo;t copy &mdash; select the IBAN and copy it manually.
        </p>
      </div>

      <p
        v-else-if="detailsError"
        class="text-center text-sm text-red-600 dark:text-red-400"
      >
        Could not load IBAN.
      </p>
    </div>
  </BaseModal>
</template>
