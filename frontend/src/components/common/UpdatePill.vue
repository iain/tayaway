<script setup lang="ts">
import { ref } from 'vue'
import { ArrowPathIcon } from '@heroicons/vue/24/outline'
import type { Notification } from '@/types/notification'

const props = defineProps<{
  notification: Notification
}>()

const loading = ref(false)

function handleClick() {
  if (loading.value) return
  loading.value = true
  props.notification.action?.()
}
</script>

<template>
  <div class="fixed bottom-6 left-1/2 z-50 -translate-x-1/2">
    <button
      type="button"
      class="flex items-center gap-2 rounded-full bg-amber-600 px-4 py-2 text-sm font-medium text-white shadow-lg active:scale-95 dark:bg-amber-700"
      @click="handleClick"
    >
      <ArrowPathIcon
        class="size-4"
        :class="loading ? 'animate-spin' : ''"
        aria-hidden="true"
      />
      Tap to update
    </button>
  </div>
</template>
