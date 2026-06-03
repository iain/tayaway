<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import AppButton from '@/components/common/AppButton.vue'
import appIcon from '@/assets/app-icon.svg'

const route = useRoute()
const router = useRouter()
const authStore = useAuthStore()

const token = route.query.token as string | undefined
const verifying = ref(false)
const error = ref(
  token ? '' : 'This link is incomplete. Open the full link from your email.'
)

async function handleSignIn() {
  if (!token) return
  verifying.value = true
  error.value = ''

  try {
    await authStore.verifyToken(token)
    router.push('/')
  } catch {
    error.value =
      'This login link has expired or was already used. Request a new one to log in.'
    verifying.value = false
  }
}
</script>

<template>
  <main
    class="bg-surface-page dark flex min-h-screen items-center justify-center"
  >
    <div class="w-full max-w-md px-6 text-center">
      <img :src="appIcon" alt="Tayaway" class="mx-auto mb-8 size-16" />
      <div v-if="!error">
        <h1 class="text-ink mb-2 text-2xl font-bold">Log in to Tayaway</h1>
        <p class="text-ink-muted mb-8 text-sm/6">
          Click the button below to complete login.
        </p>
        <AppButton
          data-testid="confirm-login"
          variant="amber"
          :loading="verifying"
          loading-label="Logging in..."
          full-width
          @click="handleSignIn"
        >
          Log in
        </AppButton>
      </div>

      <div v-else>
        <h1 class="text-ink mb-4 text-2xl font-bold">Verification Failed</h1>
        <p data-testid="verify-error" class="mb-6 text-sm text-red-400">
          {{ error }}
        </p>
        <AppButton variant="amber" to="/login">Back to login</AppButton>
      </div>
    </div>
  </main>
</template>
