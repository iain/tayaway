<script setup lang="ts">
import { onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { RouterView } from 'vue-router'
import { useAuthStore } from '@/stores'
import ToastContainer from '@/components/common/ToastContainer.vue'

const authStore = useAuthStore()
const { initialized } = storeToRefs(authStore)

onMounted(() => {
  authStore.initialize()
})
</script>

<template>
  <RouterView v-if="initialized" />
  <div v-else class="flex min-h-screen items-center justify-center bg-gray-100">
    <div class="text-gray-500">Loading...</div>
  </div>
  <ToastContainer />
</template>
