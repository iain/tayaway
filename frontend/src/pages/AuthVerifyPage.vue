<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()

const token = route.query.token as string | undefined
const verifying = ref(false)
const error = ref(token ? '' : 'Invalid magic link. Missing token.')

async function handleSignIn() {
  if (!token) return
  verifying.value = true
  error.value = ''

  try {
    await authStore.verifyToken(token)
    router.push('/')
  } catch {
    error.value = 'Invalid or expired magic link. Please request a new one.'
    verifying.value = false
  }
}
</script>

<template>
  <main class="flex min-h-screen items-center justify-center bg-stone-900">
    <div class="w-full max-w-md px-6 text-center">
      <div v-if="!error">
        <h1 class="mb-2 text-2xl font-bold text-white">Sign in to Tayaway</h1>
        <p class="mb-8 text-sm/6 text-stone-400">
          Click the button below to complete sign-in.
        </p>
        <button
          data-testid="confirm-sign-in"
          :disabled="verifying"
          class="w-full rounded-md bg-rose-500 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:cursor-not-allowed disabled:opacity-50"
          @click="handleSignIn"
        >
          {{ verifying ? 'Signing in...' : 'Sign in' }}
        </button>
      </div>

      <div v-else>
        <h1 class="mb-4 text-2xl font-bold text-white">Verification Failed</h1>
        <p data-testid="verify-error" class="mb-6 text-sm text-red-400">
          {{ error }}
        </p>
        <router-link
          to="/login"
          class="inline-block rounded-md bg-rose-500 px-4 py-2 text-sm font-semibold text-white hover:bg-rose-400"
        >
          Back to login
        </router-link>
      </div>
    </div>
  </main>
</template>
