<script setup lang="ts">
import { ref } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { FormInput } from '@/components/form'
import AppButton from '@/components/common/AppButton.vue'
import appIcon from '@/assets/app-icon.svg'

const route = useRoute()
const authStore = useAuthStore()

const email = ref('')
const message = ref('')
const error = ref('')
const loading = ref(false)
const sessionRevoked = route.query.reason === 'session_revoked'

async function handleSubmit() {
  error.value = ''
  message.value = ''
  loading.value = true

  try {
    const response = await authStore.requestLoginLink(email.value)
    message.value = response
    email.value = ''
  } catch {
    error.value =
      'Could not send the login link. Check your email address and try again.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <main class="dark flex min-h-screen items-center justify-center bg-stone-900">
    <div class="w-full max-w-md px-6">
      <img :src="appIcon" alt="Tayaway" class="mx-auto mb-8 size-16" />
      <h1
        data-testid="login-title"
        class="mb-2 text-center text-2xl font-bold text-white"
      >
        Log in to Tayaway
      </h1>
      <p class="mb-8 text-center text-sm/6 text-stone-400">
        We'll send you a login link. No password needed.
      </p>

      <div
        v-if="sessionRevoked"
        class="mb-6 rounded-md border border-amber-500/20 bg-amber-500/10 p-4"
      >
        <p class="text-sm text-amber-400">
          Your session was ended from another device. Log in again to continue.
        </p>
      </div>

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
          variant="amber"
          :disabled="!email"
          :loading="loading"
          loading-label="Sending..."
          full-width
        >
          Send login link
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
