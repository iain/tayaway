<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import type { InviteInfoResponse } from '@/types'

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
    const res = await fetch(
      `/api/invites/info?token=${encodeURIComponent(token)}`
    )
    if (!res.ok) throw new Error('Invalid invite')
    const data: InviteInfoResponse = await res.json()
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
    const res = await fetch('/api/invites/accept', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token }),
    })
    if (!res.ok) throw new Error('Accept failed')
    accepted.value = true
  } catch {
    error.value =
      'Failed to accept invitation. It may have expired or already been used.'
    accepting.value = false
  }
}
</script>

<template>
  <main class="flex min-h-screen items-center justify-center bg-stone-900">
    <div class="w-full max-w-md px-6 text-center">
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
        <router-link
          to="/login"
          class="inline-block rounded-md bg-rose-500 px-4 py-2 text-sm font-semibold text-white hover:bg-rose-400"
        >
          Go to login
        </router-link>
      </div>

      <!-- Accepted state -->
      <div v-else-if="accepted">
        <h1 class="mb-2 text-2xl font-bold text-white">
          You've joined {{ workspaceName }}
        </h1>
        <p class="mb-6 text-sm/6 text-stone-400">
          Check your email for a magic link to sign in.
        </p>
        <router-link
          to="/login"
          class="inline-block rounded-md bg-rose-500 px-4 py-2 text-sm font-semibold text-white hover:bg-rose-400"
        >
          Go to login
        </router-link>
      </div>

      <!-- Accept invitation state -->
      <div v-else>
        <h1 class="mb-2 text-2xl font-bold text-white">
          Join {{ workspaceName }}
        </h1>
        <p class="mb-8 text-sm/6 text-stone-400">
          You've been invited to join
          <strong class="text-white">{{ workspaceName }}</strong> on Tayaway.
        </p>
        <button
          data-testid="accept-invite"
          :disabled="accepting"
          class="w-full rounded-md bg-rose-500 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:cursor-not-allowed disabled:opacity-50"
          @click="handleAccept"
        >
          {{ accepting ? 'Accepting...' : 'Accept invitation' }}
        </button>
      </div>
    </div>
  </main>
</template>
