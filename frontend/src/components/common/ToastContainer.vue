<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useNotificationsStore } from '@/stores'
import ToastNotification from './ToastNotification.vue'
import UpdatePill from './UpdatePill.vue'

const notificationsStore = useNotificationsStore()
const { notifications } = storeToRefs(notificationsStore)

const toasts = computed(() =>
  notifications.value.filter((n) => n.type !== 'update')
)
const updateNotification = computed(() =>
  notifications.value.find((n) => n.type === 'update')
)
</script>

<template>
  <!-- Regular toasts (error, info) -->
  <div
    aria-live="assertive"
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
        v-for="notification in toasts"
        :key="notification.id"
        :notification="notification"
        @dismiss="notificationsStore.dismiss"
      />
    </TransitionGroup>
  </div>

  <!-- Update pill at bottom center -->
  <Transition
    enter-active-class="transition ease-out duration-300"
    enter-from-class="translate-y-full opacity-0"
    enter-to-class="translate-y-0 opacity-100"
    leave-active-class="transition ease-in duration-200"
    leave-from-class="translate-y-0 opacity-100"
    leave-to-class="translate-y-full opacity-0"
  >
    <UpdatePill v-if="updateNotification" :notification="updateNotification" />
  </Transition>
</template>
