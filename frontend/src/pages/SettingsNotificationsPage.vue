<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import type { Component } from 'vue'
import {
  BanknotesIcon,
  BellIcon,
  CalendarDaysIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/outline'
import { rawApi } from '@/api/client'
import { useNotificationsStore } from '@/stores/notifications'
import { usePushSubscription } from '@/composables/usePushSubscription'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import AppButton from '@/components/common/AppButton.vue'
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

interface KindGroup {
  key: string
  title: string
  icon: Component
  kinds: string[]
}

// Group kinds by domain so the page reads as a few related sections
// rather than a flat list. The groups are display-only — the backend
// stores preferences keyed by (kind, channel) regardless.
const GROUPS: KindGroup[] = [
  {
    key: 'workspaces',
    title: 'Workspaces',
    icon: UserGroupIcon,
    kinds: ['workspace_invite'],
  },
  {
    key: 'events',
    title: 'Events',
    icon: CalendarDaysIcon,
    kinds: ['poll_closed', 'event_details_changed'],
  },
  {
    key: 'money',
    title: 'Money',
    icon: BanknotesIcon,
    kinds: ['settlement_owed', 'settlement_owes_you', 'expense_added'],
  },
]

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
  event_details_changed: {
    label: 'Event details changed',
    description: "When dates or location change on an event you're attending.",
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
}

const CHANNEL_LABELS: Record<string, string> = {
  email: 'Email',
  in_app: 'In-app',
  push: 'Push',
}

// Fixed column order. The matrix renders these in order regardless of
// what the server returns; missing channels for a kind would show as a
// blank cell, but every kind currently supports all three.
const CHANNEL_ORDER = ['email', 'in_app', 'push'] as const

const kinds = ref<KindState[]>([])
const loading = ref(true)
const loadError = ref(false)

const push = usePushSubscription()
const pushSubscribed = ref(false)

const groupedKinds = computed(() =>
  GROUPS.map((group) => ({
    ...group,
    rows: group.kinds
      .map((key) => kinds.value.find((k) => k.key === key))
      .filter((k): k is KindState => k !== undefined),
  })).filter((g) => g.rows.length > 0)
)

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

function channelStateFor(
  kind: KindState,
  channelKey: string
): ChannelState | undefined {
  return kind.channels.find((c) => c.channel === channelKey)
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

  // Turning a push cell on while no subscription exists is otherwise a
  // silent no-op — the preference is stored but no push ever arrives.
  // Walk the user through the subscription so the toggle does what it
  // looks like it does.
  if (
    channelKey === 'push' &&
    enabled &&
    push.supported.value &&
    !pushSubscribed.value
  ) {
    const ok = await push.subscribe()
    pushSubscribed.value = ok
    if (!ok) {
      channel.enabled = previous
      if (push.error.value) {
        useNotificationsStore().showError(push.error.value)
      }
      return
    }
  }

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

// "Toggle all" semantics for a column header: if every supported cell
// in this column for this group is on, turn them all off; otherwise
// turn them all on. Skips cells where the kind doesn't support the
// channel so we never push an override the dispatcher would reject.
async function toggleColumn(
  groupKey: string,
  channelKey: string
): Promise<void> {
  const group = groupedKinds.value.find((g) => g.key === groupKey)
  if (!group) return
  const cells = group.rows.flatMap((kind) => {
    const cell = channelStateFor(kind, channelKey)
    return cell ? [{ kind, cell }] : []
  })
  if (cells.length === 0) return

  const allOn = cells.every(({ cell }) => cell.enabled)
  const target = !allOn

  await Promise.all(
    cells
      .filter(({ cell }) => cell.enabled !== target)
      .map(({ kind }) => setChannelEnabled(kind.key, channelKey, target))
  )
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
  <div class="space-y-6">
    <p class="text-sm text-gray-600 dark:text-stone-400">
      Choose how Tayaway reaches you for each kind of notification. Click a
      column header to toggle every row in the group at once.
    </p>

    <BaseCard v-if="push.supported.value" padded>
      <SectionHeading :icon="BellIcon" title="Push notifications" />
      <div class="flex items-center justify-between gap-4">
        <p class="text-sm text-gray-600 dark:text-stone-400">
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
        <AppButton
          v-if="pushSubscribed"
          variant="secondary"
          size="sm"
          @click="disablePush"
        >
          Disable
        </AppButton>
        <AppButton
          v-else
          size="sm"
          :disabled="
            push.subscribing.value || push.permission.value === 'denied'
          "
          @click="enablePush"
        >
          {{ push.subscribing.value ? 'Enabling…' : 'Enable' }}
        </AppButton>
      </div>
    </BaseCard>

    <p v-if="loading" class="text-sm text-gray-500 dark:text-stone-400">
      Loading…
    </p>

    <p v-else-if="loadError" class="text-sm text-rose-600 dark:text-rose-400">
      Couldn’t load your notification preferences.
      <button type="button" class="underline" @click="load">Try again</button>
    </p>

    <BaseCard v-for="group in groupedKinds" v-else :key="group.key" padded>
      <SectionHeading :icon="group.icon" :title="group.title" />

      <div class="overflow-x-auto">
        <table class="w-full text-left">
          <thead>
            <tr>
              <th
                class="w-full pr-4 pb-3 text-sm font-medium text-gray-500 dark:text-stone-400"
              >
                <span class="sr-only">Notification</span>
              </th>
              <th
                v-for="channelKey in CHANNEL_ORDER"
                :key="channelKey"
                scope="col"
                class="px-2 pb-3 text-center"
              >
                <button
                  type="button"
                  class="inline-flex cursor-pointer items-center justify-center rounded-md px-2 py-1 text-xs font-semibold tracking-wide text-gray-600 uppercase transition-colors hover:bg-gray-100 hover:text-gray-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-500 dark:text-stone-400 dark:hover:bg-stone-700 dark:hover:text-white"
                  :title="`Toggle every ${CHANNEL_LABELS[channelKey] ?? channelKey} row in ${group.title}`"
                  @click="toggleColumn(group.key, channelKey)"
                >
                  {{ CHANNEL_LABELS[channelKey] ?? channelKey }}
                </button>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(kind, index) in group.rows"
              :key="kind.key"
              :class="[
                'align-top',
                index > 0
                  ? 'border-t border-gray-100 dark:border-stone-700'
                  : '',
              ]"
            >
              <td class="py-3 pr-4">
                <p class="text-sm font-medium text-gray-900 dark:text-white">
                  {{ KIND_COPY[kind.key]?.label ?? kind.key }}
                </p>
                <p
                  v-if="KIND_COPY[kind.key]?.description"
                  class="mt-0.5 text-xs text-gray-600 dark:text-stone-400"
                >
                  {{ KIND_COPY[kind.key].description }}
                </p>
              </td>
              <td
                v-for="channelKey in CHANNEL_ORDER"
                :key="channelKey"
                class="px-2 py-3 text-center"
              >
                <FormToggle
                  v-if="channelStateFor(kind, channelKey)"
                  :id="toggleId(kind.key, channelKey)"
                  :model-value="channelStateFor(kind, channelKey)!.enabled"
                  :aria-label="`${KIND_COPY[kind.key]?.label ?? kind.key} via ${CHANNEL_LABELS[channelKey] ?? channelKey}`"
                  class="justify-center"
                  @update:model-value="
                    (value) => setChannelEnabled(kind.key, channelKey, value)
                  "
                />
                <span
                  v-else
                  class="text-xs text-gray-300 dark:text-stone-600"
                  aria-hidden="true"
                >
                  —
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </BaseCard>
  </div>
</template>
