<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { rawApi } from '@/api/client'
import TimeAnchor from '@/components/common/TimeAnchor.vue'
import type { Session, SessionsResponse } from '@/types'
import { useNotificationsStore } from '@/stores'
import { useLocale } from '@/composables/useLocale'
import { formatDateShort } from '@/utils/date'
import BaseCard from '@/components/common/BaseCard.vue'
import AppBadge from '@/components/common/AppBadge.vue'
import TextButton from '@/components/common/TextButton.vue'

defineProps<{
  bare?: boolean
}>()

const notifications = useNotificationsStore()
const { locale } = useLocale()
const sessions = ref<Session[]>([])
const loading = ref(true)
const error = ref<string | null>(null)

const hasOtherSessions = computed(() => sessions.value.some((s) => !s.current))
const revokingAll = ref(false)

const hasGeolocation = computed(() =>
  sessions.value.some((s) => s.city || s.country)
)

const pendingRevokes = ref<
  Map<string, { session: Session; timer: ReturnType<typeof setTimeout> }>
>(new Map())

async function fetchSessions() {
  loading.value = true
  error.value = null
  try {
    const { data } = await rawApi.get<SessionsResponse>('/auth/sessions')
    sessions.value = data.sessions
  } catch {
    error.value = 'Could not load sessions. Please try again.'
  } finally {
    loading.value = false
  }
}

function endSession(id: string) {
  const session = sessions.value.find((s) => s.id === id)
  if (!session) return

  sessions.value = sessions.value.filter((s) => s.id !== id)

  const timer = setTimeout(() => {
    executeRevoke(id)
  }, 4000)

  pendingRevokes.value.set(id, { session, timer })

  notifications.showInfo('Session revoked', {
    actionLabel: 'Undo',
    duration: 4000,
    action: () => undoRevoke(id),
  })
}

function undoRevoke(id: string) {
  const pending = pendingRevokes.value.get(id)
  if (!pending) return

  clearTimeout(pending.timer)
  pendingRevokes.value.delete(id)

  sessions.value.push(pending.session)
  sessions.value.sort(
    (a, b) =>
      new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  )
}

async function executeRevoke(id: string) {
  pendingRevokes.value.delete(id)
  try {
    await rawApi.delete(`/auth/sessions/${id}`)
  } catch {
    // Error notification handled by api client
  }
}

async function endAllOtherSessions() {
  // Cancel any pending individual revokes to avoid racing with the bulk delete
  for (const [, { timer }] of pendingRevokes.value) clearTimeout(timer)
  pendingRevokes.value.clear()

  revokingAll.value = true
  try {
    await rawApi.delete('/auth/sessions')
    sessions.value = sessions.value.filter((s) => s.current)
    notifications.showInfo('All other sessions revoked')
  } catch {
    // Error notification handled by api client
  } finally {
    revokingAll.value = false
  }
}

function formatDate(iso: string): string {
  return formatDateShort(iso, locale.value)
}

function sessionContext(session: Session): string {
  const parts: string[] = []
  if (session.browser_name || session.os_name) {
    const device = [session.browser_name, session.os_name]
      .filter(Boolean)
      .join(' on ')
    parts.push(device)
  }
  if (session.city || session.country) {
    const location = [session.city, session.country].filter(Boolean).join(', ')
    parts.push(location)
  }
  return parts.join(' \u2014 ')
}

defineExpose({
  hasOtherSessions,
  revokingAll,
  loading,
  error,
  endAllOtherSessions,
})

onMounted(fetchSessions)

onUnmounted(() => {
  for (const [id, { timer }] of pendingRevokes.value) {
    clearTimeout(timer)
    executeRevoke(id)
  }
})
</script>

<template>
  <component
    :is="bare ? 'div' : BaseCard"
    :class="bare ? undefined : 'overflow-hidden'"
  >
    <div :class="bare ? undefined : 'px-4 py-5 sm:p-6'">
      <div :class="bare ? undefined : 'space-y-4'">
        <div v-if="!bare">
          <h3
            data-testid="active-sessions-heading"
            class="text-ink text-lg font-semibold"
          >
            Active Sessions
          </h3>
          <p class="text-ink-muted mt-1 text-sm">
            Devices where you're currently signed in.
          </p>
        </div>

        <div
          v-if="loading"
          role="status"
          aria-live="polite"
          class="text-ink-muted py-4 text-sm"
        >
          Loading sessions...
        </div>

        <div
          v-else-if="error"
          role="alert"
          class="text-state-danger-ink py-4 text-sm"
        >
          {{ error }}
        </div>

        <template v-else>
          <ul
            :class="['divide-line divide-y', !bare && 'border-line border-t']"
          >
            <li
              v-for="session in sessions"
              :key="session.id"
              class="flex items-center justify-between py-4"
            >
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2">
                  <p class="text-ink truncate text-sm font-medium">
                    {{ sessionContext(session) || 'Unknown device' }}
                  </p>
                  <AppBadge
                    v-if="session.current"
                    data-testid="current-session-badge"
                    variant="success"
                  >
                    Current session
                  </AppBadge>
                </div>
                <p class="text-ink-muted mt-0.5 text-xs">
                  <template v-if="session.last_active_at">
                    <TimeAnchor :at="session.last_active_at"
                      >Last active</TimeAnchor
                    >
                    &middot;
                  </template>
                  Expires {{ formatDate(session.expires_at) }}
                </p>
              </div>
              <TextButton
                v-if="!session.current"
                variant="danger"
                class="ml-4 shrink-0"
                @click="endSession(session.id)"
              >
                Revoke
              </TextButton>
            </li>
          </ul>
        </template>

        <p v-if="hasGeolocation" class="text-ink-muted text-xs">
          IP Geolocation by
          <a
            href="https://db-ip.com"
            target="_blank"
            rel="noopener noreferrer"
            aria-label="DB-IP (opens in new tab)"
            class="hover:text-ink-muted underline"
            >DB-IP</a
          >
        </p>
      </div>
    </div>
  </component>
</template>
