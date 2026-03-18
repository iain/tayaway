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
      'This magic link has expired or was already used. Request a new one to sign in.'
    verifying.value = false
  }
}
</script>

<template>
  <main class="dark flex min-h-screen items-center justify-center bg-stone-900">
    <div class="w-full max-w-md px-6 text-center">
      <img :src="appIcon" alt="Tayaway" class="mx-auto mb-8 size-16" />
      <div v-if="!error">
        <h1 class="mb-2 text-2xl font-bold text-white">Sign in to Tayaway</h1>
        <p class="mb-8 text-sm/6 text-stone-400">
          Click the button below to complete sign-in.
        </p>
        <AppButton
          data-testid="confirm-sign-in"
          variant="amber"
          :loading="verifying"
          loading-label="Signing in..."
          full-width
          @click="handleSignIn"
        >
          Sign in
        </AppButton>
      </div>

      <div v-else>
        <h1 class="mb-4 text-2xl font-bold text-white">Verification Failed</h1>
        <p data-testid="verify-error" class="mb-6 text-sm text-red-400">
          {{ error }}
        </p>
        <AppButton variant="amber" to="/login">Back to login</AppButton>
      </div>
    </div>
  </main>
</template>
