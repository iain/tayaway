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

function handleAction(notification: Notification) {
  notification.action?.()
  emit('dismiss', notification.id)
}
</script>

<template>
  <div
    class="pointer-events-auto w-full max-w-sm overflow-hidden rounded-lg bg-white shadow-lg ring-1 ring-black/5 dark:bg-stone-800 dark:ring-white/10"
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
        <div
          class="ml-3 w-0 flex-1 pt-0.5"
          :class="
            notification.action && !notification.actionLabel
              ? 'cursor-pointer'
              : ''
          "
          @click="
            !notification.actionLabel ? notification.action?.() : undefined
          "
        >
          <p class="text-sm font-medium text-gray-900 dark:text-white">
            {{ notification.message }}
          </p>
          <button
            v-if="notification.actionLabel && notification.action"
            type="button"
            class="mt-1 text-sm font-medium text-amber-600 hover:text-amber-500 dark:text-amber-400 dark:hover:text-amber-300"
            @click="handleAction(notification)"
          >
            {{ notification.actionLabel }}
          </button>
        </div>
        <div class="ml-4 flex shrink-0">
          <button
            type="button"
            class="inline-flex rounded-md bg-white text-gray-500 hover:text-gray-700 focus-visible:ring-2 focus-visible:ring-rose-500 focus-visible:ring-offset-2 focus-visible:outline-none dark:bg-stone-800 dark:text-stone-400 dark:hover:text-stone-200 dark:focus-visible:ring-offset-stone-800"
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
