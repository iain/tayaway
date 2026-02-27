<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'

const props = defineProps<{
  open: boolean
  transferId: string | null
  recipientName: string | null
  amount: number | null
}>()

defineEmits<{
  close: []
}>()

const imgSrc = ref<string | null>(null)
const error = ref(false)

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen && props.transferId) {
      error.value = false
      imgSrc.value = `/api/settlements/transfers/${props.transferId}/qr`
    }
  }
)

function handleImgError() {
  error.value = true
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
        v-if="imgSrc && !error"
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
        v-if="error"
        class="text-center text-sm text-red-600 dark:text-red-400"
      >
        Could not generate QR code.
      </p>

      <p class="text-center text-xs text-gray-500 dark:text-stone-400">
        Scan with your banking app to pre-fill the transfer.
      </p>
    </div>
  </BaseModal>
</template>
