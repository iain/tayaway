<script setup lang="ts">
import { storeToRefs } from 'pinia'
import { useNotificationsStore } from '@/stores'
import ToastNotification from './ToastNotification.vue'

const notificationsStore = useNotificationsStore()
const { notifications } = storeToRefs(notificationsStore)
</script>

<template>
  <!-- Regular toasts (error, info). Each ToastNotification carries its own
       role — alert for error (implicit assertive), status for info (implicit
       polite) — so the container is a plain wrapper, not a live region. -->
  <div
    class="pointer-events-none fixed inset-0 z-50 flex flex-col items-end px-4 py-6 sm:p-6"
  >
    <TransitionGroup
      tag="div"
      enter-active-class="transform ease-out duration-300 transition"
      enter-from-class="translate-y-2 opacity-0 sm:translate-y-0 sm:translate-x-2"
      enter-to-class="translate-y-0 opacity-100 sm:translate-x-0"
      leave-active-class="transition ease-in duration-100"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
      class="flex w-full flex-col items-end space-y-4"
    >
      <ToastNotification
        v-for="notification in notifications"
        :key="notification.id"
        :notification="notification"
        @dismiss="notificationsStore.dismiss"
      />
    </TransitionGroup>
  </div>
</template>
