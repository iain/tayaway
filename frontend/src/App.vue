<script setup lang="ts">
import { onMounted } from 'vue'
import { RouterView } from 'vue-router'
import { useAuth } from '@/composables/useAuth'
import ToastContainer from '@/components/common/ToastContainer.vue'

const { initialize, initialized } = useAuth()

onMounted(() => {
  initialize()
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
