<script setup lang="ts">
import { ref } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { FormInput } from '@/components/form'
import AppButton from '@/components/common/AppButton.vue'

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

        <AppButton
          type="submit"
          data-testid="submit-button"
          :disabled="!email"
          :loading="loading"
          loading-label="Sending..."
          full-width
        >
          Send magic link
        </AppButton>
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
