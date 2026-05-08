<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { rawApi } from '@/api/client'
import { useNotificationsStore } from '@/stores/notifications'
import { usePushSubscription } from '@/composables/usePushSubscription'
import BaseCard from '@/components/common/BaseCard.vue'
import FormToggle from '@/components/form/FormToggle.vue'

interface ChannelState {
  channel: string
  enabled: boolean
}

interface KindState {
  key: string
  channels: ChannelState[]
}

interface PreferencesResponse {
  kinds: KindState[]
}

interface KindCopy {
  label: string
  description: string
}

// Display copy for each notification kind. Kept in the page because this
// is the only place that renders the labels — the bell shows server-rendered
// titles directly out of `data` instead of looking copy up by kind.
const KIND_COPY: Record<string, KindCopy> = {
  workspace_invite: {
    label: 'Workspace invitations',
    description: "When someone invites you to a workspace you're not in yet.",
  },
  poll_closed: {
    label: 'Event date confirmed',
    description:
      'When a date poll you voted on resolves with the chosen dates.',
  },
  settlement_owed: {
    label: 'You owe money',
    description: 'When a settlement is created and you owe someone.',
  },
  settlement_owes_you: {
    label: "You're owed money",
    description: 'When a settlement is created and someone owes you.',
  },
  expense_added: {
    label: 'Expense added',
    description:
      "When someone logs a new expense on an event you're attending.",
  },
  event_details_changed: {
    label: 'Event details changed',
    description: "When dates or location change on an event you're attending.",
  },
}

const CHANNEL_LABELS: Record<string, string> = {
  email: 'Email',
  in_app: 'In-app',
  push: 'Push',
}

const push = usePushSubscription()
const pushSubscribed = ref(false)

async function refreshPushState(): Promise<void> {
  pushSubscribed.value = await push.isSubscribed()
}

async function enablePush(): Promise<void> {
  const ok = await push.subscribe()
  pushSubscribed.value = ok
  if (!ok && push.error.value) {
    useNotificationsStore().showError(push.error.value)
  }
}

async function disablePush(): Promise<void> {
  await push.unsubscribe()
  pushSubscribed.value = false
}

const kinds = ref<KindState[]>([])
const loading = ref(true)
const loadError = ref(false)

async function load(): Promise<void> {
  loading.value = true
  loadError.value = false
  try {
    const { data } = await rawApi.get<PreferencesResponse>(
      '/notifications/preferences'
    )
    kinds.value = data.kinds
  } catch {
    loadError.value = true
  } finally {
    loading.value = false
  }
}

async function setChannelEnabled(
  kindKey: string,
  channelKey: string,
  enabled: boolean
): Promise<void> {
  const kind = kinds.value.find((k) => k.key === kindKey)
  const channel = kind?.channels.find((c) => c.channel === channelKey)
  if (!channel) return

  const previous = channel.enabled
  channel.enabled = enabled

  try {
    await rawApi.put(
      '/notifications/preferences',
      { kind: kindKey, channel: channelKey, enabled },
      { silent: true }
    )
  } catch {
    channel.enabled = previous
    useNotificationsStore().showError("Couldn't save that change. Try again.")
  }
}

function toggleId(kindKey: string, channelKey: string): string {
  return `notif-${kindKey}-${channelKey}`
}

onMounted(() => {
  void load()
  void refreshPushState()
})
</script>

<template>
  <div class="space-y-4">
    <p class="text-sm text-gray-600 dark:text-stone-400">
      Choose how Tayaway reaches you for each kind of notification.
    </p>

    <BaseCard
      v-if="push.supported.value"
      padded
      class="bg-white dark:bg-stone-900"
    >
      <div class="flex items-center justify-between gap-4">
        <div>
          <h3 class="text-base font-semibold text-gray-900 dark:text-white">
            Push notifications
          </h3>
          <p class="mt-1 text-sm text-gray-600 dark:text-stone-400">
            <template v-if="pushSubscribed">
              Push is enabled on this device. Per-kind preferences below control
              which alerts come through.
            </template>
            <template v-else-if="push.permission.value === 'denied'">
              Notifications are blocked in your browser. Allow them in your site
              settings to enable push.
            </template>
            <template v-else>
              Get alerts on this device when something time-sensitive happens.
            </template>
          </p>
        </div>
        <button
          v-if="pushSubscribed"
          type="button"
          class="shrink-0 rounded-md bg-gray-100 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-200 dark:bg-stone-700 dark:text-stone-200 dark:hover:bg-stone-600"
          @click="disablePush"
        >
          Disable
        </button>
        <button
          v-else
          type="button"
          :disabled="
            push.subscribing.value || push.permission.value === 'denied'
          "
          class="shrink-0 rounded-md bg-rose-500 px-3 py-1.5 text-sm font-medium text-white hover:bg-rose-600 disabled:cursor-not-allowed disabled:opacity-50"
          @click="enablePush"
        >
          {{ push.subscribing.value ? 'Enabling…' : 'Enable' }}
        </button>
      </div>
    </BaseCard>

    <p v-if="loading" class="text-sm text-gray-500 dark:text-stone-400">
      Loading…
    </p>

    <p v-else-if="loadError" class="text-sm text-rose-600 dark:text-rose-400">
      Couldn’t load your notification preferences.
      <button type="button" class="underline" @click="load">Try again</button>
    </p>

    <BaseCard
      v-for="kind in kinds"
      v-else
      :key="kind.key"
      padded
      class="bg-white dark:bg-stone-900"
    >
      <div class="flex flex-col gap-4">
        <div>
          <h3 class="text-base font-semibold text-gray-900 dark:text-white">
            {{ KIND_COPY[kind.key]?.label ?? kind.key }}
          </h3>
          <p
            v-if="KIND_COPY[kind.key]?.description"
            class="mt-1 text-sm text-gray-600 dark:text-stone-400"
          >
            {{ KIND_COPY[kind.key].description }}
          </p>
        </div>

        <div class="flex flex-col gap-3">
          <div
            v-for="channel in kind.channels"
            :key="channel.channel"
            class="flex items-center justify-between"
          >
            <label
              :for="toggleId(kind.key, channel.channel)"
              class="text-sm font-medium text-gray-900 dark:text-white"
            >
              {{ CHANNEL_LABELS[channel.channel] ?? channel.channel }}
            </label>
            <FormToggle
              :id="toggleId(kind.key, channel.channel)"
              :model-value="channel.enabled"
              :aria-label="`${KIND_COPY[kind.key]?.label ?? kind.key} via ${CHANNEL_LABELS[channel.channel] ?? channel.channel}`"
              @update:model-value="
                (value) => setChannelEnabled(kind.key, channel.channel, value)
              "
            />
          </div>
        </div>
      </div>
    </BaseCard>
  </div>
</template>
