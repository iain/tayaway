<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()

const verifying = ref(true)
const error = ref('')

onMounted(async () => {
  const token = route.query.token as string | undefined
  const email = route.query.email as string | undefined

  if (!token || !email) {
    error.value = 'Invalid magic link. Missing token or email.'
    verifying.value = false
    return
  }

  try {
    await authStore.verifyToken(token, email)
    router.push('/')
  } catch {
    error.value = 'Invalid or expired magic link. Please request a new one.'
    verifying.value = false
  }
})
</script>

<template>
  <main class="min-h-screen bg-gray-100 dark:bg-gray-900 flex items-center justify-center">
    <div class="bg-white dark:bg-gray-800 p-8 rounded-lg shadow-md text-center">
      <div v-if="verifying">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">
          Verifying...
        </h1>
        <p class="text-gray-500 dark:text-gray-400">
          Please wait while we sign you in.
        </p>
      </div>

      <div v-else-if="error">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">
          Verification Failed
        </h1>
        <p class="text-red-600 dark:text-red-400 mb-4">
          {{ error }}
        </p>
        <router-link
          to="/login"
          class="inline-block py-2 px-4 bg-rose-600 text-white font-medium rounded-md hover:bg-rose-700"
        >
          Back to login
        </router-link>
      </div>
    </div>
  </main>
</template>
