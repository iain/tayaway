<script setup lang="ts">
import { ref, watch } from 'vue'
import { XMarkIcon } from '@heroicons/vue/24/outline'
import FormInput from '@/components/form/FormInput.vue'

const props = defineProps<{
  open: boolean
  loading?: boolean
}>()

const emit = defineEmits<{
  close: []
  save: [name: string, email: string]
}>()

const dialogRef = ref<HTMLDialogElement | null>(null)
const name = ref('')
const email = ref('')

watch(() => props.open, (isOpen) => {
  if (isOpen) {
    name.value = ''
    email.value = ''
    dialogRef.value?.showModal()
  } else {
    dialogRef.value?.close()
  }
})

function handleSave(): void {
  if (email.value.trim()) {
    emit('save', name.value.trim(), email.value.trim())
  }
}

function handleClose(): void {
  emit('close')
}
</script>

<template>
  <dialog
    ref="dialogRef"
    class="m-auto rounded-lg bg-gray-900 p-6 text-left shadow-xl backdrop:bg-gray-900/75 sm:w-full sm:max-w-md"
    @close="handleClose"
  >
    <div class="absolute right-0 top-0 pr-4 pt-4">
      <button
        type="button"
        class="rounded-md bg-gray-900 text-gray-400 hover:text-gray-300 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 focus:ring-offset-gray-900"
        @click="handleClose"
      >
        <span class="sr-only">Close</span>
        <XMarkIcon
          class="size-6"
          aria-hidden="true"
        />
      </button>
    </div>

    <h3 class="text-lg font-semibold text-white mb-6">
      Add New User
    </h3>

    <form
      class="space-y-4"
      @submit.prevent="handleSave"
    >
      <FormInput
        id="user-name"
        v-model="name"
        label="Name"
        placeholder="Enter name (optional)"
        autocomplete="name"
        autofocus
        :disabled="loading"
      />
      <FormInput
        id="user-email"
        v-model="email"
        label="Email"
        type="email"
        placeholder="Enter email"
        autocomplete="email"
        required
        :disabled="loading"
      />

      <div class="mt-6 flex items-center justify-end gap-x-6">
        <button
          type="button"
          class="text-sm/6 font-semibold text-white"
          :disabled="loading"
          @click="handleClose"
        >
          Cancel
        </button>
        <button
          type="submit"
          data-testid="modal-save-button"
          class="rounded-md bg-indigo-500 px-3 py-2 text-sm font-semibold text-white hover:bg-indigo-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="!email.trim() || loading"
        >
          {{ loading ? 'Adding...' : 'Add User' }}
        </button>
      </div>
    </form>
  </dialog>
</template>
