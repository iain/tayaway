<script setup lang="ts">
import {
  ExclamationCircleIcon,
  InformationCircleIcon,
  XMarkIcon,
} from '@heroicons/vue/24/outline'
import type { Notification } from '@/types/notification'

defineProps<{
  notification: Notification
}>()

const emit = defineEmits<{
  dismiss: [id: string]
}>()
</script>

<template>
  <div
    class="pointer-events-auto w-full max-w-sm overflow-hidden rounded-lg bg-white shadow-lg ring-1 ring-black/5 dark:bg-gray-800 dark:ring-white/10"
  >
    <div class="p-4">
      <div class="flex items-start">
        <div class="shrink-0">
          <InformationCircleIcon
            v-if="notification.type === 'info'"
            class="size-6 text-blue-500 dark:text-blue-400"
            aria-hidden="true"
          />
          <ExclamationCircleIcon
            v-else
            class="size-6 text-red-500 dark:text-red-400"
            aria-hidden="true"
          />
        </div>
        <div class="ml-3 w-0 flex-1 pt-0.5">
          <p class="text-sm font-medium text-gray-900 dark:text-white">
            {{ notification.type === 'info' ? 'Info' : 'Error' }}
          </p>
          <p class="mt-1 text-sm text-gray-600 dark:text-gray-300">
            {{ notification.message }}
          </p>
        </div>
        <div class="ml-4 flex shrink-0">
          <button
            type="button"
            class="inline-flex rounded-md bg-white text-gray-500 hover:text-gray-700 focus:ring-2 focus:ring-rose-500 focus:ring-offset-2 focus:outline-none dark:bg-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:ring-offset-gray-800"
            @click="emit('dismiss', notification.id)"
          >
            <span class="sr-only">Close</span>
            <XMarkIcon class="size-5" aria-hidden="true" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
