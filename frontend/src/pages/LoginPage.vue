<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { FormInput } from '@/components/form'
import AppButton from '@/components/common/AppButton.vue'
import { KeyIcon } from '@heroicons/vue/24/outline'
import appIcon from '@/assets/app-icon.svg'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()

const email = ref('')
const message = ref('')
const error = ref('')
const loading = ref(false)
const passkeyLoading = ref(false)
const passkeyAvailable = ref(false)
const sessionRevoked = route.query.reason === 'session_revoked'

const abortController = ref<AbortController | null>(null)

async function handleSubmit() {
  // Abort any pending conditional mediation when the user submits the email form
  abortController.value?.abort()
  abortController.value = null

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

async function handlePasskeyLogin() {
  error.value = ''
  message.value = ''
  passkeyLoading.value = true

  try {
    await authStore.authenticateWithPasskey()
    router.push('/')
  } catch (e) {
    // Don't show error if user cancelled the ceremony
    if (e instanceof Error && e.name === 'NotAllowedError') return
    error.value = 'Passkey authentication failed. Please try again.'
  } finally {
    passkeyLoading.value = false
  }
}

onMounted(async () => {
  // Check if WebAuthn is available
  if (!window.PublicKeyCredential) return
  passkeyAvailable.value = true

  // Start conditional mediation (passkey autofill) if supported
  const available =
    typeof PublicKeyCredential.isConditionalMediationAvailable === 'function' &&
    (await PublicKeyCredential.isConditionalMediationAvailable())
  if (!available) return

  try {
    abortController.value = new AbortController()
    await authStore.authenticateWithPasskey({
      mediation: 'conditional',
      signal: abortController.value.signal,
    })
    router.push('/')
  } catch {
    // User cancelled or passkey failed — fall through to email form
  }
})

onUnmounted(() => {
  abortController.value?.abort()
})
</script>

<template>
  <main
    class="dark bg-surface-page flex min-h-screen flex-col items-center justify-center px-4"
  >
    <div class="w-full max-w-md">
      <img :src="appIcon" alt="Tayaway" class="mx-auto mb-8 size-16" />
    </div>
    <div
      class="border-line w-full max-w-md rounded-xl border bg-stone-800/40 p-8 shadow-xl sm:p-10"
    >
      <h1
        data-testid="login-title"
        class="text-ink mb-2 text-center text-2xl font-bold"
      >
        Log in to Tayaway
      </h1>
      <p class="text-ink-muted mb-8 text-center text-sm/6">
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
          autocomplete="email webauthn"
          autofocus
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

      <div v-if="passkeyAvailable" class="mt-4">
        <div class="my-4 flex items-center gap-3">
          <div class="h-px flex-1 bg-stone-700" />
          <span class="text-ink-muted text-sm">or</span>
          <div class="h-px flex-1 bg-stone-700" />
        </div>

        <AppButton
          data-testid="passkey-login-button"
          variant="secondary"
          :loading="passkeyLoading"
          loading-label="Authenticating..."
          full-width
          @click="handlePasskeyLogin"
        >
          <KeyIcon class="size-4" />
          Sign in with a passkey
        </AppButton>
      </div>

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
