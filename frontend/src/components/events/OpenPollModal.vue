<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormActions from '@/components/form/FormActions.vue'
import { datetimeLocalToIso, isFutureIso } from '@/utils/date'
import { defaultPollDeadline } from '@/utils/poll'

const props = defineProps<{
  open: boolean
  title?: string
  loading?: boolean
  autofocusSubmit?: boolean
}>()

const emit = defineEmits<{
  close: []
  confirm: [deadline: string]
}>()

const deadline = ref('')

// Set default deadline to 7 days from now when opened
watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      deadline.value = defaultPollDeadline()
    }
  },
  { immediate: true }
)

const canConfirm = computed(() => {
  if (!deadline.value) return false
  return isFutureIso(deadline.value)
})

function handleConfirm(): void {
  if (!canConfirm.value) return
  emit('confirm', datetimeLocalToIso(deadline.value))
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <BaseModal
    :open="open"
    :title="title || 'Open Date Poll'"
    size="md"
    @close="handleClose"
  >
    <form @submit.prevent="handleConfirm">
      <div class="space-y-4">
        <div>
          <label for="deadline" class="text-ink block text-sm/6 font-medium">
            Voting Deadline
          </label>
          <p class="text-ink-muted mt-1 text-sm">
            Set when voting closes. You can always close it early or reopen
            later.
          </p>
          <input
            id="deadline"
            v-model="deadline"
            type="datetime-local"
            class="text-ink bg-surface-sunken ring-line mt-2 block w-full rounded-md border-0 px-3 py-1.5 shadow-sm ring-1 ring-inset focus:ring-2 focus:ring-rose-500 focus:ring-inset sm:text-sm/6"
          />
        </div>
      </div>

      <FormActions
        submit-label="Open Poll"
        loading-label="Creating..."
        :loading="loading"
        :disabled="!canConfirm"
        :autofocus-submit="autofocusSubmit"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
