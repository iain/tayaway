<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '@/composables/useAuth'

const router = useRouter()
const { isAuthenticated, requestMagicLink } = useAuth()

const email = ref('')
const message = ref('')
const error = ref('')
const loading = ref(false)

if (isAuthenticated.value) {
  router.push('/')
}

async function handleSubmit() {
  error.value = ''
  message.value = ''
  loading.value = true

  try {
    const response = await requestMagicLink(email.value)
    message.value = response
    email.value = ''
  } catch {
    error.value = 'Failed to send magic link. Please try again.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <main class="min-h-screen bg-gray-100 flex items-center justify-center">
    <div class="bg-white p-8 rounded-lg shadow-md w-full max-w-md">
      <h1 class="text-2xl font-bold text-gray-900 mb-6 text-center">
        Sign in to Tayaway
      </h1>

      <form
        class="space-y-4"
        @submit.prevent="handleSubmit"
      >
        <div>
          <label
            for="email"
            class="block text-sm font-medium text-gray-700 mb-1"
          >
            Email address
          </label>
          <input
            id="email"
            v-model="email"
            type="email"
            required
            placeholder="you@example.com"
            class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            :disabled="loading"
          >
        </div>

        <button
          type="submit"
          :disabled="loading || !email"
          class="w-full py-2 px-4 bg-blue-600 text-white font-medium rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {{ loading ? 'Sending...' : 'Send magic link' }}
        </button>
      </form>

      <div
        v-if="message"
        class="mt-4 p-3 bg-green-50 border border-green-200 rounded-md text-green-700 text-sm"
      >
        {{ message }}
      </div>

      <div
        v-if="error"
        class="mt-4 p-3 bg-red-50 border border-red-200 rounded-md text-red-700 text-sm"
      >
        {{ error }}
      </div>

      <p class="mt-6 text-center text-sm text-gray-500">
        We'll send you a magic link to sign in without a password.
      </p>
    </div>
  </main>
</template>
