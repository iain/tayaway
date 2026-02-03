<script setup lang="ts">
import { ref } from 'vue'
import { useAuthStore } from '@/stores'
import { FormInput } from '@/components/form'

const authStore = useAuthStore()

const email = ref('')
const message = ref('')
const error = ref('')
const loading = ref(false)

async function handleSubmit() {
  error.value = ''
  message.value = ''
  loading.value = true

  try {
    const response = await authStore.requestMagicLink(email.value)
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
  <main class="min-h-screen bg-gray-900 flex items-center justify-center">
    <div class="w-full max-w-md px-6">
      <h1
        data-testid="login-title"
        class="text-2xl font-bold text-white mb-2 text-center"
      >
        Sign in to Tayaway
      </h1>
      <p class="text-sm/6 text-gray-400 text-center mb-8">
        We'll send you a magic link to sign in without a password.
      </p>

      <form
        class="space-y-6"
        @submit.prevent="handleSubmit"
      >
        <FormInput
          id="email"
          v-model="email"
          label="Email address"
          type="email"
          placeholder="you@example.com"
          autocomplete="email"
          required
          :disabled="loading"
          data-testid="email-input"
        />

        <button
          type="submit"
          data-testid="submit-button"
          :disabled="loading || !email"
          class="w-full rounded-md bg-indigo-500 px-3 py-2 text-sm font-semibold text-white hover:bg-indigo-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {{ loading ? 'Sending...' : 'Send magic link' }}
        </button>
      </form>

      <div
        v-if="message"
        data-testid="success-message"
        class="mt-6 rounded-md bg-green-500/10 p-4 border border-green-500/20"
      >
        <p class="text-sm text-green-400">
          {{ message }}
        </p>
      </div>

      <div
        v-if="error"
        class="mt-6 rounded-md bg-red-500/10 p-4 border border-red-500/20"
      >
        <p class="text-sm text-red-400">
          {{ error }}
        </p>
      </div>
    </div>
  </main>
</template>
