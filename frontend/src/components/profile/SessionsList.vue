<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { api } from '@/api/client'
import { formatRelativeDate, formatDateShort } from '@/utils/date'
import type { Session, SessionsResponse } from '@/types'
import BaseCard from '@/components/common/BaseCard.vue'
import AppBadge from '@/components/common/AppBadge.vue'

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
    error.value = 'Could not load sessions. Please try again.'
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

function formatDate(iso: string): string {
  return formatDateShort(iso)
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
            <AppBadge
              v-if="session.current"
              data-testid="current-session-badge"
              variant="green"
            >
              Current session
            </AppBadge>
          </div>
          <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
            <span v-if="session.last_active_at"
              >Last active
              {{ formatRelativeDate(session.last_active_at) }} &middot; </span
            >Expires {{ formatDate(session.expires_at) }}
          </p>
        </div>
        <button
          v-if="!session.current"
          type="button"
          :disabled="deletingId === session.id"
          class="ml-4 shrink-0 rounded-md px-3 py-2 text-sm font-medium text-red-600 transition-colors hover:text-red-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:opacity-50 dark:text-red-400 dark:hover:text-red-300"
          @click="endSession(session.id)"
        >
          {{ deletingId === session.id ? 'Revoking...' : 'Revoke' }}
        </button>
      </li>
    </ul>
  </div>

  <!-- Default mode: full card with heading -->
  <BaseCard v-else class="overflow-hidden">
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
                <AppBadge
                  v-if="session.current"
                  data-testid="current-session-badge"
                  variant="green"
                >
                  Current session
                </AppBadge>
              </div>
              <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
                <span v-if="session.last_active_at"
                  >Last active
                  {{
                    formatRelativeDate(session.last_active_at)
                  }}
                  &middot; </span
                >Expires {{ formatDate(session.expires_at) }}
              </p>
            </div>
            <button
              v-if="!session.current"
              type="button"
              :disabled="deletingId === session.id"
              class="ml-4 shrink-0 rounded-md px-3 py-2 text-sm font-medium text-red-600 transition-colors hover:text-red-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 disabled:opacity-50 dark:text-red-400 dark:hover:text-red-300"
              @click="endSession(session.id)"
            >
              {{ deletingId === session.id ? 'Revoking...' : 'Revoke' }}
            </button>
          </li>
        </ul>
      </div>
    </div>
  </BaseCard>
</template>
