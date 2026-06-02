<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import type { Component } from 'vue'
import {
  BanknotesIcon,
  BellIcon,
  CalendarDaysIcon,
  ShieldCheckIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/outline'
import { rawApi } from '@/api/client'
import { useNotificationsStore } from '@/stores/notifications'
import { usePushSubscription } from '@/composables/usePushSubscription'
import {
  chipState,
  chipWrites,
  type ChannelKey,
  type ChipState,
  type KindState,
} from '@/composables/useChannelChips'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import ChannelChip from '@/components/notifications/ChannelChip.vue'

interface PreferencesResponse {
  kinds: KindState[]
}

interface Group {
  key: string
  title: string
  blurb: string
  icon: Component
  kinds: string[]
  forcedReason: Partial<Record<ChannelKey, string>>
}

const GROUPS: Group[] = [
  {
    key: 'security',
    title: 'Account & security',
    blurb: 'Sign-ins, passkey changes, and email updates.',
    icon: ShieldCheckIcon,
    kinds: ['new_session', 'passkey_changed', 'email_change_completed'],
    forcedReason: { email: 'Security alerts always reach you by email.' },
  },
  {
    key: 'workspaces',
    title: 'Workspaces',
    blurb: 'Invitations, role changes, and accepted invites.',
    icon: UserGroupIcon,
    kinds: [
      'workspace_invite',
      'workspace_invite_accepted',
      'member_role_changed',
    ],
    forcedReason: {},
  },
  {
    key: 'events',
    title: 'Events',
    blurb:
      'New events, cancellations, date or location changes, and polls closing.',
    icon: CalendarDaysIcon,
    kinds: [
      'event_created',
      'event_canceled',
      'event_details_changed',
      'poll_closed',
    ],
    forcedReason: {},
  },
  {
    key: 'money',
    title: 'Money',
    blurb: 'Settlements, payment marks, and new expenses on shared events.',
    icon: BanknotesIcon,
    kinds: ['settlement_created', 'payment_status_changed', 'expense_added'],
    forcedReason: {},
  },
]

const CHANNEL_ORDER: ChannelKey[] = ['email', 'in_app', 'push']
const CHANNEL_LABELS: Record<ChannelKey, string> = {
  email: 'Email',
  in_app: 'In-app',
  push: 'Push',
}

const kinds = ref<KindState[]>([])
const loading = ref(true)
const loadError = ref(false)
const saving = ref(new Set<string>())
const sendingTest = ref(false)

const push = usePushSubscription()
const pushSubscribed = ref(false)

const groups = computed(() =>
  GROUPS.map((group) => {
    const rows = group.kinds
      .map((key) => kinds.value.find((k) => k.key === key))
      .filter((k): k is KindState => k !== undefined)
    return {
      ...group,
      rows,
      chips: CHANNEL_ORDER.map((channel) => ({
        channel,
        label: CHANNEL_LABELS[channel],
        state: chipState(rows, channel),
        forcedReason: group.forcedReason[channel],
        savingKey: `${group.key}-${channel}`,
      })),
    }
  }).filter((g) => g.rows.length > 0)
)

// One-line summary footer — shows only when something is locked anywhere on
// the page, so the user knows where the floor is.
const forcedFooterParts = computed(() => {
  const parts: string[] = []
  for (const group of groups.value) {
    for (const chip of group.chips) {
      if (chip.state.kind === 'forced' && chip.forcedReason) {
        parts.push(chip.forcedReason)
      }
    }
  }
  // Workspace invites force every channel but are deliberately not chipped
  // as forced (the chip aggregates *configurable* rows; the forced invite
  // row is silent in the chip). Surface the rule in the footer instead.
  const hasInviteForced = kinds.value.some(
    (k) => k.key === 'workspace_invite' && k.channels.some((c) => c.forced)
  )
  if (hasInviteForced) {
    parts.push(
      "Workspace invitations always reach you, since that's how you get into a workspace."
    )
  }
  return Array.from(new Set(parts))
})

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

async function sendTestPush(): Promise<void> {
  if (sendingTest.value) return
  sendingTest.value = true
  const toast = useNotificationsStore()
  try {
    await rawApi.post(
      '/notifications/push-subscriptions/test',
      {},
      { silent: true }
    )
    toast.showInfo('Test push sent. It should arrive in a moment.')
  } catch (err) {
    const message =
      err instanceof Error && err.message
        ? err.message
        : "Couldn't send a test push."
    toast.showError(message)
  } finally {
    sendingTest.value = false
  }
}

function denyHelpHint(): string {
  if (typeof navigator === 'undefined') return ''
  const ua = navigator.userAgent
  if (/iPhone|iPad|iPod/.test(ua)) {
    return 'On iOS, install Tayaway to your home screen first, then enable notifications from there.'
  }
  if (/Firefox/.test(ua)) {
    return 'In Firefox, click the lock icon in the address bar, then set Notifications to Allow.'
  }
  if (/Safari/.test(ua) && !/Chrome|Chromium/.test(ua)) {
    return 'In Safari, open Settings, choose Websites, then Notifications, and allow this site.'
  }
  return 'Click the lock or settings icon in your address bar, then set Notifications to Allow.'
}

async function flipChip(
  groupKey: string,
  channel: ChannelKey,
  state: ChipState
): Promise<void> {
  if (state.kind !== 'configurable') return

  const target = !state.enabled
  const group = groups.value.find((g) => g.key === groupKey)
  if (!group) return

  const writes = chipWrites(group.rows, channel, target)
  if (writes.length === 0) return

  // If turning push on without a device subscription, walk the user through
  // the subscribe flow first. Without this, the preference is stored but
  // no push ever arrives.
  if (
    channel === 'push' &&
    target === true &&
    push.supported.value &&
    !pushSubscribed.value
  ) {
    const ok = await push.subscribe()
    pushSubscribed.value = ok
    if (!ok) {
      if (push.error.value) {
        useNotificationsStore().showError(push.error.value)
      }
      return
    }
  }

  const savingKey = `${groupKey}-${channel}`
  saving.value.add(savingKey)
  saving.value = new Set(saving.value)

  // Optimistic local update so the chip flips immediately.
  const previous: { kindKey: string; enabled: boolean }[] = []
  for (const write of writes) {
    const kind = kinds.value.find((k) => k.key === write.kindKey)
    const cell = kind?.channels.find((c) => c.channel === channel)
    if (!cell) continue
    previous.push({ kindKey: write.kindKey, enabled: cell.enabled })
    cell.enabled = write.enabled
  }

  try {
    await Promise.all(
      writes.map((write) =>
        rawApi.put(
          '/notifications/preferences',
          {
            kind: write.kindKey,
            channel: write.channel,
            enabled: write.enabled,
          },
          { silent: true }
        )
      )
    )
  } catch {
    for (const item of previous) {
      const kind = kinds.value.find((k) => k.key === item.kindKey)
      const cell = kind?.channels.find((c) => c.channel === channel)
      if (cell) cell.enabled = item.enabled
    }
    useNotificationsStore().showError("Couldn't save that change. Try again.")
  } finally {
    saving.value.delete(savingKey)
    saving.value = new Set(saving.value)
  }
}

onMounted(() => {
  void load()
  void refreshPushState()
})
</script>

<template>
  <div class="space-y-6">
    <section v-if="push.supported.value">
      <SectionHeading :icon="BellIcon" title="Push notifications" />
      <BaseCard padded>
        <div
          class="flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between sm:gap-4"
        >
          <p class="text-ink-muted">
            <template v-if="pushSubscribed">
              Push is on for this device.
            </template>
            <template v-else-if="push.permission.value === 'denied'">
              Notifications are blocked in your browser. {{ denyHelpHint() }}
            </template>
            <template v-else>
              Get alerts on this device when something time-sensitive happens.
            </template>
          </p>
          <div class="flex shrink-0 flex-wrap items-center gap-2">
            <AppButton
              v-if="pushSubscribed"
              variant="secondary"
              size="sm"
              :disabled="sendingTest"
              @click="sendTestPush"
            >
              {{ sendingTest ? 'Sending…' : 'Send a test' }}
            </AppButton>
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
        </div>
      </BaseCard>
    </section>

    <BaseCard v-if="loading" padded aria-busy="true">
      <ul class="divide-line divide-y">
        <li
          v-for="group in GROUPS"
          :key="`skel-${group.key}`"
          class="flex flex-col gap-4 py-5 first:pt-0 last:pb-0 sm:flex-row sm:items-center sm:justify-between sm:gap-8"
        >
          <div class="min-w-0 flex-1">
            <h3
              class="text-ink flex items-center gap-2 text-base font-semibold"
            >
              <component
                :is="group.icon"
                class="size-5 text-amber-600 dark:text-amber-400"
                aria-hidden="true"
              />
              {{ group.title }}
            </h3>
            <p class="text-ink-muted mt-0.5 text-sm">
              {{ group.blurb }}
            </p>
          </div>
          <div class="flex shrink-0 flex-wrap gap-2">
            <span
              v-for="i in 3"
              :key="i"
              class="bg-btn-secondary-fill h-9 w-20 animate-pulse rounded-full"
            />
          </div>
        </li>
      </ul>
    </BaseCard>

    <BaseCard v-else-if="loadError" padded variant="urgent">
      <p
        role="alert"
        class="flex flex-wrap items-center gap-x-2 gap-y-1 text-rose-700 dark:text-rose-300"
      >
        <span>Couldn’t load your notification preferences.</span>
        <TextButton @click="load">Try again</TextButton>
      </p>
    </BaseCard>

    <template v-else>
      <BaseCard padded>
        <ul class="divide-line divide-y">
          <li
            v-for="group in groups"
            :key="group.key"
            class="flex flex-col gap-4 py-5 first:pt-0 last:pb-0 sm:flex-row sm:items-center sm:justify-between sm:gap-8"
          >
            <div class="min-w-0 flex-1">
              <h3
                class="text-ink flex items-center gap-2 text-base font-semibold"
              >
                <component
                  :is="group.icon"
                  class="size-5 text-amber-600 dark:text-amber-400"
                  aria-hidden="true"
                />
                {{ group.title }}
              </h3>
              <p class="text-ink-muted mt-0.5 text-sm">
                {{ group.blurb }}
              </p>
            </div>
            <div
              class="flex shrink-0 flex-wrap gap-2"
              role="group"
              :aria-label="`Channels for ${group.title}`"
            >
              <template v-for="chip in group.chips" :key="chip.channel">
                <ChannelChip
                  v-if="chip.state.kind !== 'hidden'"
                  :state="
                    chip.state.kind === 'forced'
                      ? 'forced'
                      : chip.state.enabled
                        ? 'on'
                        : 'off'
                  "
                  :label="chip.label"
                  :saving="saving.has(chip.savingKey)"
                  :forced-reason="chip.forcedReason"
                  @toggle="flipChip(group.key, chip.channel, chip.state)"
                />
              </template>
            </div>
          </li>
        </ul>
      </BaseCard>

      <p v-if="forcedFooterParts.length > 0" class="text-ink-muted text-sm">
        {{ forcedFooterParts.join(' ') }}
      </p>
    </template>
  </div>
</template>
