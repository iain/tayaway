<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { rawApi } from '@/api/client'
import { useNotificationsStore } from '@/stores/notifications'
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

// Display copy for each notification kind. Kept in the page (rather than
// a constant module) because this is the only place that renders them;
// when we add a notification center in slice 3 it can read its own copy
// from the same backend response shape.
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
}

const CHANNEL_LABELS: Record<string, string> = {
  email: 'Email',
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

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <p class="text-sm text-gray-600 dark:text-stone-400">
      Choose how Tayaway reaches you for each kind of notification.
    </p>

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
