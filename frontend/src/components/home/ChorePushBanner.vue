<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { BellAlertIcon } from '@heroicons/vue/24/outline'
import { rawApi } from '@/api/client'
import { useNotificationsStore } from '@/stores/notifications'
import { usePushSubscription } from '@/composables/usePushSubscription'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'

// Dismissal is a personal, per-device choice — localStorage, not the shared
// object pool, mirroring useTaskListPrefs.
const STORAGE_KEY = 'tayaway:home:chore-push-nudge-dismissed'

const router = useRouter()
const push = usePushSubscription()

function loadDismissed(): boolean {
  try {
    return localStorage.getItem(STORAGE_KEY) === '1'
  } catch {
    return false
  }
}

const dismissed = ref(loadDismissed())

// null = subscription state not checked yet; the nudge stays hidden until the
// check resolves so already-subscribed devices never see it flash.
const deviceSubscribed = ref<boolean | null>(null)

onMounted(async () => {
  deviceSubscribed.value = await push.isSubscribed()
})

const visible = computed(
  () =>
    push.supported.value &&
    push.permission.value !== 'denied' &&
    deviceSubscribed.value === false &&
    !dismissed.value
)

function dismiss(): void {
  dismissed.value = true
  try {
    localStorage.setItem(STORAGE_KEY, '1')
  } catch {
    // Best effort — private mode just loses the persistence.
  }
}

async function enable(): Promise<void> {
  // Subscribe before navigating: the permission prompt needs this click's
  // user gesture, which routing to the settings page would burn.
  const ok = await push.subscribe()
  if (ok) {
    try {
      await rawApi.put(
        '/notifications/preferences',
        { kind: 'chore_reminder', channel: 'push', enabled: true },
        { silent: true }
      )
    } catch {
      // The settings page we land on shows the real chip state, so a lost
      // write is visible and fixable there.
    }
  } else if (push.error.value) {
    useNotificationsStore().showError(push.error.value)
  }
  router.push({ name: 'settings-notifications' })
}
</script>

<template>
  <div
    v-if="visible"
    data-testid="chore-push-banner"
    class="rounded-xl border border-amber-200 bg-amber-50/50 p-4 sm:p-6 dark:border-amber-800/40 dark:bg-amber-950/20"
  >
    <div
      class="flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between sm:gap-4"
    >
      <p class="text-ink-muted flex items-start gap-3">
        <BellAlertIcon
          class="mt-0.5 size-5 shrink-0 text-amber-600 dark:text-amber-400"
          aria-hidden="true"
        />
        <span>
          You have chores coming up. Enable push notifications and we&rsquo;ll
          remind you on this device when it&rsquo;s your turn.
        </span>
      </p>
      <div class="flex shrink-0 flex-wrap items-center gap-2">
        <AppButton
          size="sm"
          :loading="push.subscribing.value"
          loading-label="Enabling…"
          data-testid="chore-push-enable"
          @click="enable"
        >
          Enable reminders
        </AppButton>
        <TextButton
          variant="secondary"
          data-testid="chore-push-dismiss"
          @click="dismiss"
        >
          Not now
        </TextButton>
      </div>
    </div>
  </div>
</template>
