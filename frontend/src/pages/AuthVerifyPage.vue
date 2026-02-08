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
  <main
    class="flex min-h-screen items-center justify-center bg-gray-100 dark:bg-gray-900"
  >
    <div class="rounded-lg bg-white p-8 text-center shadow-md dark:bg-gray-800">
      <div v-if="verifying">
        <h1 class="mb-4 text-2xl font-bold text-gray-900 dark:text-white">
          Verifying...
        </h1>
        <p class="text-gray-500 dark:text-gray-400">
          Please wait while we sign you in.
        </p>
      </div>

      <div v-else-if="error">
        <h1 class="mb-4 text-2xl font-bold text-gray-900 dark:text-white">
          Verification Failed
        </h1>
        <p class="mb-4 text-red-600 dark:text-red-400">
          {{ error }}
        </p>
        <router-link
          to="/login"
          class="inline-block rounded-md bg-rose-600 px-4 py-2 font-medium text-white hover:bg-rose-700"
        >
          Back to login
        </router-link>
      </div>
    </div>
  </main>
</template>
