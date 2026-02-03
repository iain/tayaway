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
  <div
    v-else
    class="min-h-screen bg-gray-100 flex items-center justify-center"
  >
    <div class="text-gray-500">
      Loading...
    </div>
  </div>
  <ToastContainer />
</template>
