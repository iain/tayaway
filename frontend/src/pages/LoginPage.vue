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
  <main class="flex min-h-screen items-center justify-center bg-stone-900">
    <div class="w-full max-w-md px-6">
      <h1
        data-testid="login-title"
        class="mb-2 text-center text-2xl font-bold text-white"
      >
        Sign in to Tayaway
      </h1>
      <p class="mb-8 text-center text-sm/6 text-stone-400">
        We'll send you a magic link to sign in without a password.
      </p>

      <form class="space-y-6" @submit.prevent="handleSubmit">
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
          class="w-full rounded-md bg-rose-500 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {{ loading ? 'Sending...' : 'Send magic link' }}
        </button>
      </form>

      <div
        v-if="message"
        data-testid="success-message"
        class="mt-6 rounded-md border border-green-500/20 bg-green-500/10 p-4"
      >
        <p class="text-sm text-green-400">
          {{ message }}
        </p>
      </div>

      <div
        v-if="error"
        class="mt-6 rounded-md border border-red-500/20 bg-red-500/10 p-4"
      >
        <p class="text-sm text-red-400">
          {{ error }}
        </p>
      </div>
    </div>
  </main>
</template>
