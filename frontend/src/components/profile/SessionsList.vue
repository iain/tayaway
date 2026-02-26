<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { api } from '@/api/client'
import type { Session, SessionsResponse } from '@/types'

defineProps<{
  bare?: boolean
}>()

const sessions = ref<Session[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const deletingId = ref<string | null>(null)

async function fetchSessions() {
  loading.value = true
  error.value = null
  try {
    const { data } = await api.get<SessionsResponse>('/auth/sessions')
    sessions.value = data.sessions
  } catch {
    error.value = 'Failed to load sessions.'
  } finally {
    loading.value = false
  }
}

async function endSession(id: string) {
  deletingId.value = id
  try {
    await api.delete(`/auth/sessions/${id}`)
    sessions.value = sessions.value.filter((s) => s.id !== id)
  } catch {
    // Error notification handled by api client
  } finally {
    deletingId.value = null
  }
}

function formatRelativeDate(iso: string): string {
  const date = new Date(iso)
  const now = new Date()
  const diffMs = now.getTime() - date.getTime()
  const diffMinutes = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMs / 3600000)
  const diffDays = Math.floor(diffMs / 86400000)

  if (diffMinutes < 1) return 'Just now'
  if (diffMinutes < 60) return `${diffMinutes}m ago`
  if (diffHours < 24) return `${diffHours}h ago`
  if (diffDays < 30) return `${diffDays}d ago`
  return date.toLocaleDateString()
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  })
}

onMounted(fetchSessions)
</script>

<template>
  <!-- Bare mode: just the session list content, no card wrapper -->
  <div v-if="bare">
    <div v-if="loading" class="py-4 text-sm text-gray-500 dark:text-stone-400">
      Loading sessions...
    </div>

    <div v-else-if="error" class="py-4 text-sm text-red-600 dark:text-red-400">
      {{ error }}
    </div>

    <ul v-else class="divide-y divide-gray-200 dark:divide-stone-700">
      <li
        v-for="session in sessions"
        :key="session.id"
        class="flex items-center justify-between py-4"
      >
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <p class="text-sm font-medium text-gray-900 dark:text-white">
              Created {{ formatRelativeDate(session.created_at) }}
            </p>
            <span
              v-if="session.current"
              data-testid="current-session-badge"
              class="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700 dark:bg-green-900 dark:text-green-300"
            >
              Current session
            </span>
          </div>
          <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
            Expires {{ formatDate(session.expires_at) }}
          </p>
        </div>
        <button
          v-if="!session.current"
          type="button"
          :disabled="deletingId === session.id"
          class="ml-4 shrink-0 text-sm font-medium text-red-600 hover:text-red-500 disabled:opacity-50 dark:text-red-400 dark:hover:text-red-300"
          @click="endSession(session.id)"
        >
          {{ deletingId === session.id ? 'Ending...' : 'End session' }}
        </button>
      </li>
    </ul>
  </div>

  <!-- Default mode: full card with heading -->
  <div
    v-else
    class="overflow-hidden rounded-lg bg-white shadow dark:bg-stone-800"
  >
    <div class="px-4 py-5 sm:p-6">
      <div class="space-y-4">
        <div>
          <h3
            data-testid="active-sessions-heading"
            class="text-lg font-medium text-gray-900 dark:text-white"
          >
            Active Sessions
          </h3>
          <p class="mt-1 text-sm text-gray-500 dark:text-stone-400">
            Devices where you're currently signed in.
          </p>
        </div>

        <div
          v-if="loading"
          class="py-4 text-sm text-gray-500 dark:text-stone-400"
        >
          Loading sessions...
        </div>

        <div
          v-else-if="error"
          class="py-4 text-sm text-red-600 dark:text-red-400"
        >
          {{ error }}
        </div>

        <ul
          v-else
          class="divide-y divide-gray-200 border-t border-gray-200 dark:divide-stone-700 dark:border-stone-700"
        >
          <li
            v-for="session in sessions"
            :key="session.id"
            class="flex items-center justify-between py-4"
          >
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <p class="text-sm font-medium text-gray-900 dark:text-white">
                  Created {{ formatRelativeDate(session.created_at) }}
                </p>
                <span
                  v-if="session.current"
                  data-testid="current-session-badge"
                  class="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-700 dark:bg-green-900 dark:text-green-300"
                >
                  Current session
                </span>
              </div>
              <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
                Expires {{ formatDate(session.expires_at) }}
              </p>
            </div>
            <button
              v-if="!session.current"
              type="button"
              :disabled="deletingId === session.id"
              class="ml-4 shrink-0 text-sm font-medium text-red-600 hover:text-red-500 disabled:opacity-50 dark:text-red-400 dark:hover:text-red-300"
              @click="endSession(session.id)"
            >
              {{ deletingId === session.id ? 'Ending...' : 'End session' }}
            </button>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
