<script setup lang="ts">
import {
  ArrowPathIcon,
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
    class="pointer-events-auto w-full max-w-sm overflow-hidden rounded-lg shadow-lg ring-1"
    :class="
      notification.type === 'update'
        ? 'bg-amber-50 ring-amber-200 dark:bg-amber-950 dark:ring-amber-800'
        : 'bg-white ring-black/5 dark:bg-stone-800 dark:ring-white/10'
    "
  >
    <div class="p-4">
      <div class="flex items-start">
        <div class="shrink-0">
          <ArrowPathIcon
            v-if="notification.type === 'update'"
            class="size-6 text-amber-600 dark:text-amber-400"
            aria-hidden="true"
          />
          <InformationCircleIcon
            v-else-if="notification.type === 'info'"
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
          :class="notification.action ? 'cursor-pointer' : ''"
          @click="notification.action?.()"
        >
          <p
            class="text-sm font-medium"
            :class="
              notification.type === 'update'
                ? 'text-amber-900 dark:text-amber-100'
                : 'text-gray-900 dark:text-white'
            "
          >
            {{
              notification.type === 'update'
                ? 'Update Available'
                : notification.type === 'info'
                  ? 'Info'
                  : 'Error'
            }}
          </p>
          <p
            class="mt-1 text-sm"
            :class="
              notification.type === 'update'
                ? 'text-amber-800 dark:text-amber-200'
                : 'text-gray-600 dark:text-stone-300'
            "
          >
            {{ notification.message }}
          </p>
        </div>
        <div class="ml-4 flex shrink-0">
          <button
            type="button"
            class="inline-flex rounded-md text-gray-500 hover:text-gray-700 focus:ring-2 focus:ring-rose-500 focus:ring-offset-2 focus:outline-none"
            :class="
              notification.type === 'update'
                ? 'bg-amber-50 dark:bg-amber-950 dark:text-amber-400 dark:hover:text-amber-200 dark:focus:ring-offset-amber-950'
                : 'bg-white dark:bg-stone-800 dark:text-stone-400 dark:hover:text-stone-200 dark:focus:ring-offset-stone-800'
            "
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
