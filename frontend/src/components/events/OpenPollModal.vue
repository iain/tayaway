<script setup lang="ts">
import { ref, watch, computed } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormActions from '@/components/form/FormActions.vue'

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
      const defaultDate = new Date()
      defaultDate.setDate(defaultDate.getDate() + 7)
      defaultDate.setHours(23, 59, 0, 0)
      // Format for datetime-local input
      const year = defaultDate.getFullYear()
      const month = String(defaultDate.getMonth() + 1).padStart(2, '0')
      const day = String(defaultDate.getDate()).padStart(2, '0')
      const hours = String(defaultDate.getHours()).padStart(2, '0')
      const minutes = String(defaultDate.getMinutes()).padStart(2, '0')
      deadline.value = `${year}-${month}-${day}T${hours}:${minutes}`
    }
  },
  { immediate: true }
)

const canConfirm = computed(() => {
  if (!deadline.value) return false
  return new Date(deadline.value) > new Date()
})

function handleConfirm(): void {
  if (!canConfirm.value) return
  emit('confirm', new Date(deadline.value).toISOString())
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
            class="text-ink mt-2 block w-full rounded-md border-0 bg-white/5 px-3 py-1.5 shadow-sm ring-1 ring-gray-300 ring-inset focus:ring-2 focus:ring-rose-500 focus:ring-inset sm:text-sm/6 dark:ring-stone-700"
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
