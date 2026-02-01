<script setup lang="ts">
import { ref } from 'vue'
import { useAuth } from '@/composables/useAuth'

const { requestMagicLink } = useAuth()

const email = ref('')
const message = ref('')
const error = ref('')
const loading = ref(false)

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
  <main class="min-h-screen bg-gray-100 dark:bg-gray-900 flex items-center justify-center">
    <div class="bg-white dark:bg-gray-800 p-8 rounded-lg shadow-md w-full max-w-md">
      <h1
        data-testid="login-title"
        class="text-2xl font-bold text-gray-900 dark:text-white mb-6 text-center"
      >
        Sign in to Tayaway
      </h1>

      <form
        class="space-y-4"
        @submit.prevent="handleSubmit"
      >
        <div>
          <label
            for="email"
            class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1"
          >
            Email address
          </label>
          <input
            id="email"
            v-model="email"
            type="email"
            required
            data-testid="email-input"
            placeholder="you@example.com"
            class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm bg-white dark:bg-gray-700 text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
            :disabled="loading"
          >
        </div>

        <button
          type="submit"
          data-testid="submit-button"
          :disabled="loading || !email"
          class="w-full py-2 px-4 bg-indigo-600 text-white font-medium rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {{ loading ? 'Sending...' : 'Send magic link' }}
        </button>
      </form>

      <div
        v-if="message"
        data-testid="success-message"
        class="mt-4 p-3 bg-green-50 dark:bg-green-900/30 border border-green-200 dark:border-green-800 rounded-md text-green-700 dark:text-green-400 text-sm"
      >
        {{ message }}
      </div>

      <div
        v-if="error"
        class="mt-4 p-3 bg-red-50 dark:bg-red-900/30 border border-red-200 dark:border-red-800 rounded-md text-red-700 dark:text-red-400 text-sm"
      >
        {{ error }}
      </div>

      <p class="mt-6 text-center text-sm text-gray-500 dark:text-gray-400">
        We'll send you a magic link to sign in without a password.
      </p>
    </div>
  </main>
</template>
