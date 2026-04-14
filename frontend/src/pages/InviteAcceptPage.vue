<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { rawApi } from '@/api/client'
import type { InviteInfoResponse } from '@/types'
import AppButton from '@/components/common/AppButton.vue'
import appIcon from '@/assets/app-icon.svg'

const route = useRoute()

const token = route.query.token as string | undefined
const loading = ref(true)
const accepting = ref(false)
const workspaceName = ref('')
const email = ref('')
const error = ref(token ? '' : 'Invalid invitation link. Missing token.')
const accepted = ref(false)

onMounted(async () => {
  if (!token) {
    loading.value = false
    return
  }

  try {
    const { data } = await rawApi.get<InviteInfoResponse>(
      `/invites/info?token=${encodeURIComponent(token)}`
    )
    workspaceName.value = data.workspaceName
    email.value = data.email
  } catch {
    error.value =
      'This invitation is no longer valid. It may have expired or already been used.'
  } finally {
    loading.value = false
  }
})

async function handleAccept() {
  if (!token) return
  accepting.value = true
  error.value = ''

  try {
    await rawApi.post('/invites/accept', { token }, { silent: true })
    accepted.value = true
  } catch {
    error.value =
      'Failed to accept invitation. It may have expired or already been used.'
    accepting.value = false
  }
}
</script>

<template>
  <main class="dark flex min-h-screen items-center justify-center bg-stone-900">
    <div class="w-full max-w-md px-6 text-center">
      <img :src="appIcon" alt="Tayaway" class="mx-auto mb-8 size-16" />

      <!-- Loading state -->
      <div v-if="loading">
        <p class="text-stone-400">Loading invitation...</p>
      </div>

      <!-- Error state -->
      <div v-else-if="error">
        <h1 class="mb-4 text-2xl font-bold text-white">Invitation Invalid</h1>
        <p class="mb-6 text-sm text-red-400">
          {{ error }}
        </p>
        <AppButton variant="amber" to="/login">Go to login</AppButton>
      </div>

      <!-- Accepted state -->
      <div v-else-if="accepted">
        <h1 class="mb-2 text-2xl font-bold text-white">
          You've joined {{ workspaceName }}
        </h1>
        <p class="mb-6 text-sm/6 text-stone-400">
          Check your email for a login link.
        </p>
        <AppButton variant="amber" to="/login">Go to login</AppButton>
      </div>

      <!-- Accept invitation state -->
      <div v-else>
        <h1 class="mb-8 text-2xl font-bold text-white">
          Join {{ workspaceName }}
        </h1>
        <AppButton
          data-testid="accept-invite"
          variant="amber"
          :loading="accepting"
          loading-label="Accepting..."
          full-width
          @click="handleAccept"
        >
          Accept invitation
        </AppButton>
      </div>
    </div>
  </main>
</template>
