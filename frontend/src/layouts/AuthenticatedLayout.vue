<script setup lang="ts">
import { computed, ref, watchEffect } from 'vue'
import { storeToRefs } from 'pinia'
import { useRouter, useRoute } from 'vue-router'
import {
  Disclosure,
  DisclosureButton,
  DisclosurePanel,
  Menu,
  MenuButton,
  MenuItem,
  MenuItems,
} from '@headlessui/vue'
import {
  Bars3Icon,
  XMarkIcon,
  SunIcon,
  MoonIcon,
  ChevronDownIcon,
  MagnifyingGlassIcon,
  XCircleIcon,
} from '@heroicons/vue/24/outline'
import {
  useAuthStore,
  useWebSocketStore,
  useWorkspaceStore,
  useCommandQueueStore,
} from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useInboxStore } from '@/stores/inbox'
import { useDarkMode } from '@/composables/useDarkMode'
import { useMinuteTicker } from '@/composables/useMinuteTicker'
import {
  getStaleness,
  staleDays,
  type StalenessLevel,
} from '@/composables/useStaleness'
import TimeAnchor from '@/components/common/TimeAnchor.vue'
import { getInitials } from '@/utils/member'
import AppAvatar from '@/components/common/AppAvatar.vue'
import CommandPalette from '@/components/common/CommandPalette.vue'
import NotificationBell from '@/components/common/NotificationBell.vue'
import UnreadDot from '@/components/common/UnreadDot.vue'
import EventSubheader from '@/components/events/EventSubheader.vue'
import { useCommandPalette } from '@/composables/useCommandPalette'
import { useEventContextCommands } from '@/composables/useEventContextCommands'

useEventContextCommands()

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()
const wsStore = useWebSocketStore()
const workspaceStore = useWorkspaceStore()
const commandQueueStore = useCommandQueueStore()
const objectPoolStore = useObjectPoolStore()
const { user } = storeToRefs(authStore)
const {
  state: wsState,
  hasSynced,
  hasCachedData,
  connectionFailed,
} = storeToRefs(wsStore)
const { pendingCount, isProcessing, retryScheduled } =
  storeToRefs(commandQueueStore)

const showConnectionBadge = computed(() => wsState.value !== 'authenticated')

// Surface queued offline work whenever it exists: socket down, replay in
// progress, or a backoff retry armed (fetch failed while the socket stayed
// up). Direct in-flight mutations also bump pendingCount but match none of
// these, so normal online clicks don't flash the pill.
const showPendingPill = computed(
  () =>
    pendingCount.value > 0 &&
    (wsState.value !== 'authenticated' ||
      isProcessing.value ||
      retryScheduled.value)
)
const { currentWorkspace, otherWorkspaces } = storeToRefs(workspaceStore)
const inboxStore = useInboxStore()
const { unreadCountByOtherWorkspace } = storeToRefs(inboxStore)

// Staleness indicators tick once a minute via the shared minute ticker so
// "fresh" → "stale" → "warning" advances without a page refresh, and so the
// nav agrees with every `<TimeAnchor>` on what "now" means.
const { now } = useMinuteTicker()

// Staleness tier derived locally from the persisted syncedAt + `now`, so it
// advances in-place while the user is offline. Returns null once a live sync
// has arrived (the UI collapses to the connected state then).
const cacheStaleLevel = computed<StalenessLevel | null>(() => {
  if (hasSynced.value) return null
  const since = wsStore.getSyncedAt(workspaceStore.currentWorkspaceId ?? '')
  if (!since) return null
  return getStaleness(since, now.value)
})

// Timestamp the staleness indicator anchors to (ISO string for `<TimeAnchor>`).
const lastSyncedAt = computed<string | null>(() => {
  const since = wsStore.getSyncedAt(workspaceStore.currentWorkspaceId ?? '')
  return since ?? null
})

// Show "Last synced" only when we have stale cached data and are connected
// (the connection badge already shows status when disconnected)
const showLastSynced = computed(
  () =>
    !showConnectionBadge.value &&
    !hasSynced.value &&
    cacheStaleLevel.value === 'stale' &&
    lastSyncedAt.value !== null
)

// Dismissible warning banner for caches 1–7 days old
const warningBannerDismissed = ref(false)
const showWarningBanner = computed(
  () =>
    !hasSynced.value &&
    cacheStaleLevel.value === 'warning' &&
    !warningBannerDismissed.value
)

const warningBannerDays = computed(() => {
  const since = wsStore.getSyncedAt(workspaceStore.currentWorkspaceId ?? '')
  if (!since) return 1
  return staleDays(since, now.value)
})

const { isDark, toggle: toggleDarkMode } = useDarkMode()
const { open: openCommandPalette } = useCommandPalette()

const navigation = [
  { name: 'Dashboard', href: '/', routeName: 'home' },
  { name: 'Events', href: '/events', routeName: 'events' },
  { name: 'Tasks', href: '/tasks', routeName: 'tasks' },
  { name: 'Settle up', href: '/settle-up', routeName: 'settle-up' },
  { name: 'Members', href: '/members', routeName: 'members' },
]

const userNavigation = [{ name: 'Settings', href: '/settings' }]

const currentRouteName = computed(() => route.name)

const eventDetailRoutes = new Set([
  'event',
  'event-planning',
  'event-planning-vote',
  'event-planning-date-ranges',
  'event-rsvp',
  'event-expenses',
  'event-chores',
])

const currentEvent = computed(() => {
  const name = route.name as string
  const id = route.params.id as string | undefined
  if (!id || !eventDetailRoutes.has(name)) return null
  return objectPoolStore.get('event', id) ?? null
})

const currentEventName = computed(() => currentEvent.value?.name ?? null)

const routeTitleMap: Record<string, string> = {
  home: 'Dashboard',
  settings: 'Settings',
  'settings-profile': 'Profile · Settings',
  'settings-login': 'Login · Settings',
  'settings-payment': 'Payment · Settings',
  events: 'Events',
  'events-new': 'New Event',
  event: '',
  'event-planning': 'Planning',
  'event-planning-vote': 'Vote',
  'event-planning-date-ranges': 'Date Ranges',
  'event-rsvp': 'RSVP',
  'event-expenses': 'Expenses',
  'event-chores': 'Chores',
  tasks: 'Tasks',
  members: 'Members',
}

watchEffect(() => {
  const parts: string[] = []
  const routeName = route.name as string
  const pageTitle = routeTitleMap[routeName]
  if (pageTitle !== undefined) {
    if (eventDetailRoutes.has(routeName)) {
      if (pageTitle) parts.push(pageTitle)
      if (currentEventName.value) parts.push(currentEventName.value)
    } else if (pageTitle) {
      parts.push(pageTitle)
    }
  }
  if (currentWorkspace.value?.name) parts.push(currentWorkspace.value.name)
  document.title = parts.length > 0 ? parts.join(' - ') : 'Tayaway'
})

function isActive(routeName: string): boolean {
  const currentName = currentRouteName.value as string
  if (routeName === 'events') {
    return currentName === 'events' || currentName?.startsWith('event')
  }
  return currentName === routeName
}

async function handleSignOut() {
  await authStore.logout()
  router.push('/login')
}
</script>

<template>
  <!-- Loading screen while waiting for initial sync -->
  <div
    v-if="!hasSynced && !hasCachedData && !connectionFailed"
    class="bg-surface-page flex min-h-screen flex-col items-center justify-center"
  >
    <div class="text-center">
      <div
        class="inline-block h-12 w-12 animate-spin rounded-full border-4 border-amber-600 border-t-transparent"
      />
      <p class="text-ink mt-4 text-lg font-medium">Loading...</p>
    </div>
  </div>

  <div v-else class="min-h-full">
    <!-- Staleness warning banner (1–7 days old cache) -->
    <Transition
      enter-active-class="transition ease-out duration-200"
      enter-from-class="-translate-y-full opacity-0"
      enter-to-class="translate-y-0 opacity-100"
      leave-active-class="transition ease-in duration-150"
      leave-from-class="translate-y-0 opacity-100"
      leave-to-class="-translate-y-full opacity-0"
    >
      <div
        v-if="showWarningBanner"
        class="bg-state-warning-fill text-state-warning-ink relative flex items-center justify-between gap-x-4 px-4 py-2 text-sm font-medium sm:px-6"
        role="alert"
      >
        <p>
          You've been offline for {{ warningBannerDays }}
          {{ warningBannerDays === 1 ? 'day' : 'days' }}. Some data may be
          outdated.
        </p>
        <button
          type="button"
          class="-mr-1 shrink-0 rounded p-1 hover:bg-black/5 dark:hover:bg-white/10"
          aria-label="Dismiss"
          @click="warningBannerDismissed = true"
        >
          <XCircleIcon class="size-5" aria-hidden="true" />
        </button>
      </div>
    </Transition>

    <Disclosure
      v-slot="{ open, close }"
      as="nav"
      class="bg-nav sticky top-0 z-40"
    >
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div class="flex h-16 items-center justify-between">
          <div class="flex items-center">
            <div class="shrink-0">
              <!-- Single workspace: just show name -->
              <router-link
                v-if="otherWorkspaces.length === 0"
                to="/"
                class="text-nav-text rounded text-xl font-bold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
              >
                {{ currentWorkspace?.name ?? 'Tayaway' }}
              </router-link>
              <!-- Multiple workspaces: name links to dashboard, chevron opens dropdown -->
              <div v-else class="relative flex items-center gap-0.5">
                <router-link
                  to="/"
                  class="text-nav-text rounded text-xl font-bold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
                >
                  {{ currentWorkspace?.name ?? 'Tayaway' }}
                </router-link>
                <Menu as="div" class="relative">
                  <MenuButton
                    data-testid="workspace-switcher-trigger"
                    aria-label="Switch workspace"
                    class="text-nav-text hover:text-nav-text-muted-hover flex items-center focus:outline-hidden"
                  >
                    <ChevronDownIcon class="size-5" aria-hidden="true" />
                  </MenuButton>
                  <transition
                    enter-active-class="transition ease-out duration-100"
                    enter-from-class="transform opacity-0 scale-95"
                    enter-to-class="transform opacity-100 scale-100"
                    leave-active-class="transition ease-in duration-75"
                    leave-from-class="transform opacity-100 scale-100"
                    leave-to-class="transform opacity-0 scale-95"
                  >
                    <MenuItems
                      class="bg-surface ring-ring-hairline absolute left-0 z-10 mt-2 w-56 origin-top-left rounded-md py-1 shadow-lg ring-1 focus:outline-hidden"
                    >
                      <MenuItem
                        v-for="ws in otherWorkspaces"
                        :key="ws.id"
                        v-slot="{ active }"
                      >
                        <button
                          type="button"
                          data-testid="workspace-switcher-option"
                          :data-workspace-id="ws.id"
                          :class="[
                            active ? 'bg-btn-secondary-fill' : '',
                            'text-ink flex w-full items-center justify-between px-4 py-2 text-left text-sm',
                          ]"
                          @click="workspaceStore.switchWorkspace(ws.id)"
                        >
                          <span>{{ ws.name }}</span>
                          <UnreadDot
                            :count="unreadCountByOtherWorkspace.get(ws.id) ?? 0"
                          />
                        </button>
                      </MenuItem>
                    </MenuItems>
                  </transition>
                </Menu>
              </div>
            </div>
            <div class="hidden md:block">
              <div class="ml-10 flex items-baseline space-x-4">
                <router-link
                  v-for="item in navigation"
                  :key="item.name"
                  :to="item.href"
                  :class="[
                    isActive(item.routeName)
                      ? 'bg-nav-active text-nav-text shadow-[inset_0_1px_2px_rgba(0,0,0,0.15)] dark:shadow-[inset_0_1px_2px_rgba(0,0,0,0.35)]'
                      : 'text-nav-text hover:bg-nav-hover',
                    'rounded-md px-3 py-2 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white',
                  ]"
                  :aria-current="isActive(item.routeName) ? 'page' : undefined"
                >
                  {{ item.name }}
                </router-link>
              </div>
            </div>
          </div>
          <div class="hidden md:block">
            <div class="ml-4 flex items-center md:ml-6">
              <!-- Stale cache indicator: "Last synced X ago" -->
              <TimeAnchor
                v-if="showLastSynced && lastSyncedAt"
                :at="lastSyncedAt"
                class="text-ink-muted mr-3 text-xs"
                >Last synced</TimeAnchor
              >

              <!-- Connection status badge -->
              <button
                v-if="showConnectionBadge"
                type="button"
                class="mr-3 inline-flex cursor-pointer items-center gap-1.5 rounded-full bg-gray-900/40 px-3 py-1 text-xs font-medium text-white transition-colors hover:bg-gray-900/60"
                title="Click to reconnect"
                @click="wsStore.reconnect()"
              >
                <span class="inline-block size-2 rounded-full bg-gray-300" />
                Offline
              </button>

              <!-- Dark mode toggle -->
              <button
                type="button"
                class="bg-nav text-nav-text-muted hover:text-nav-text relative rounded-full p-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
                @click="toggleDarkMode"
              >
                <span class="sr-only">Toggle dark mode</span>
                <SunIcon v-if="isDark" class="size-6" aria-hidden="true" />
                <MoonIcon v-else class="size-6" aria-hidden="true" />
              </button>

              <!-- Notifications inbox -->
              <NotificationBell class="ml-2" />

              <!-- Profile dropdown -->
              <Menu as="div" class="relative ml-3">
                <div>
                  <MenuButton
                    data-testid="user-menu-button"
                    class="bg-nav relative flex max-w-xs items-center rounded-full text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
                  >
                    <span class="sr-only">Open user menu</span>
                    <AppAvatar
                      data-testid="user-initial"
                      :initials="user ? getInitials(user) : '?'"
                      size="sm"
                      variant="nav"
                    />
                  </MenuButton>
                </div>
                <transition
                  enter-active-class="transition ease-out duration-100"
                  enter-from-class="transform opacity-0 scale-95"
                  enter-to-class="transform opacity-100 scale-100"
                  leave-active-class="transition ease-in duration-75"
                  leave-from-class="transform opacity-100 scale-100"
                  leave-to-class="transform opacity-0 scale-95"
                >
                  <MenuItems
                    class="bg-surface ring-ring-hairline absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md py-1 shadow-lg ring-1 focus:outline-hidden"
                  >
                    <div
                      class="border-line text-ink truncate border-b px-4 py-2 text-sm"
                    >
                      {{ user?.email }}
                    </div>
                    <MenuItem
                      v-for="item in userNavigation"
                      :key="item.name"
                      v-slot="{ active, close: closeMenu }"
                    >
                      <button
                        type="button"
                        :class="[
                          active ? 'bg-btn-secondary-fill' : '',
                          'text-ink block w-full px-4 py-2 text-left text-sm',
                        ]"
                        @click="
                          () => {
                            closeMenu()
                            router.push(item.href)
                          }
                        "
                      >
                        {{ item.name }}
                      </button>
                    </MenuItem>
                    <MenuItem v-slot="{ active }">
                      <button
                        type="button"
                        data-testid="log-out-button"
                        :class="[
                          active ? 'bg-btn-secondary-fill' : '',
                          'text-ink block w-full px-4 py-2 text-left text-sm',
                        ]"
                        @click="handleSignOut"
                      >
                        Log out
                      </button>
                    </MenuItem>
                  </MenuItems>
                </transition>
              </Menu>
            </div>
          </div>
          <div class="-mr-2 flex md:hidden">
            <!-- Mobile menu button -->
            <DisclosureButton
              class="group bg-nav text-nav-text-muted hover:bg-nav-hover hover:text-nav-text relative inline-flex items-center justify-center rounded-md p-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
            >
              <span class="sr-only">Open main menu</span>
              <Bars3Icon
                :class="['size-6', open ? 'hidden' : 'block']"
                aria-hidden="true"
              />
              <XMarkIcon
                :class="['size-6', open ? 'block' : 'hidden']"
                aria-hidden="true"
              />
            </DisclosureButton>
          </div>
        </div>
      </div>

      <DisclosurePanel class="md:hidden">
        <!-- Mobile workspace switcher -->
        <div
          v-if="otherWorkspaces.length > 0"
          class="border-nav-active border-b px-3 pt-2 pb-3"
        >
          <p
            class="text-nav-text-muted px-2 text-xs font-semibold tracking-wide uppercase"
          >
            Switch workspace
          </p>
          <button
            v-for="ws in otherWorkspaces"
            :key="ws.id"
            type="button"
            class="text-nav-text hover:bg-nav-hover mt-1 flex w-full items-center justify-between rounded-md px-3 py-2 text-left text-base font-medium"
            @click="
              () => {
                close()
                void workspaceStore.switchWorkspace(ws.id)
              }
            "
          >
            <span>{{ ws.name }}</span>
            <UnreadDot :count="unreadCountByOtherWorkspace.get(ws.id) ?? 0" />
          </button>
        </div>
        <div class="space-y-1 px-2 pt-2 pb-3 sm:px-3">
          <router-link
            v-for="item in navigation"
            :key="item.name"
            :to="item.href"
            :class="[
              isActive(item.routeName)
                ? 'bg-nav-active text-nav-text shadow-[inset_0_1px_2px_rgba(0,0,0,0.15)] dark:shadow-[inset_0_1px_2px_rgba(0,0,0,0.35)]'
                : 'text-nav-text hover:bg-nav-hover',
              'block rounded-md px-3 py-2 text-base font-medium',
            ]"
            :aria-current="isActive(item.routeName) ? 'page' : undefined"
            @click="close"
          >
            {{ item.name }}
          </router-link>
          <button
            type="button"
            class="text-nav-text hover:bg-nav-hover flex w-full items-center gap-2 rounded-md px-3 py-2 text-base font-medium"
            @click="
              () => {
                close()
                openCommandPalette()
              }
            "
          >
            <MagnifyingGlassIcon class="size-5" aria-hidden="true" />
            Search
          </button>
        </div>
        <div class="border-nav-active border-t pt-4 pb-3">
          <div class="flex items-center px-5">
            <div class="shrink-0">
              <AppAvatar
                :initials="user ? getInitials(user) : '?'"
                variant="nav"
              />
            </div>
            <div class="ml-3 min-w-0 flex-1">
              <div class="text-nav-text truncate text-base font-medium">
                {{ user?.email }}
              </div>
              <!-- Mobile stale cache indicator -->
              <TimeAnchor
                v-if="showLastSynced && lastSyncedAt"
                :at="lastSyncedAt"
                class="text-ink-muted block text-xs"
                >Last synced</TimeAnchor
              >
            </div>
            <button
              v-if="showConnectionBadge"
              type="button"
              class="ml-auto inline-flex cursor-pointer items-center gap-1.5 rounded-full bg-gray-900/40 px-3 py-1 text-xs font-medium text-white transition-colors hover:bg-gray-900/60"
              title="Click to reconnect"
              @click="wsStore.reconnect()"
            >
              <span class="inline-block size-2 rounded-full bg-gray-300" />
              Offline
            </button>
            <button
              type="button"
              class="bg-nav text-nav-text-muted hover:text-nav-text shrink-0 rounded-full p-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
              :class="!showConnectionBadge ? 'relative ml-auto' : 'ml-2'"
              @click="toggleDarkMode"
            >
              <span class="sr-only">Toggle dark mode</span>
              <SunIcon v-if="isDark" class="size-6" aria-hidden="true" />
              <MoonIcon v-else class="size-6" aria-hidden="true" />
            </button>
          </div>
          <div class="mt-3 space-y-1 px-2">
            <router-link
              v-for="item in userNavigation"
              :key="item.name"
              :to="item.href"
              class="text-nav-text hover:bg-nav-hover block rounded-md px-3 py-2 text-base font-medium"
              @click="close"
            >
              {{ item.name }}
            </router-link>
            <button
              type="button"
              class="text-nav-text hover:bg-nav-hover block w-full rounded-md px-3 py-2 text-left text-base font-medium"
              @click="
                () => {
                  close()
                  handleSignOut()
                }
              "
            >
              Log out
            </button>
          </div>
        </div>
      </DisclosurePanel>
    </Disclosure>

    <header v-if="$slots.header" class="bg-surface shadow">
      <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <slot name="header" />
      </div>
    </header>

    <!-- Event subheader -->
    <EventSubheader v-if="currentEvent" :event="currentEvent" />

    <main>
      <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <RouterView />
      </div>
    </main>
  </div>

  <CommandPalette />

  <!-- Pending changes indicator -->
  <Transition
    enter-active-class="transition ease-out duration-300"
    enter-from-class="translate-y-full opacity-0"
    enter-to-class="translate-y-0 opacity-100"
    leave-active-class="transition ease-in duration-200"
    leave-from-class="translate-y-0 opacity-100"
    leave-to-class="translate-y-full opacity-0"
  >
    <div
      v-if="showPendingPill"
      data-testid="pending-changes-pill"
      class="fixed bottom-20 left-1/2 z-50 -translate-x-1/2"
    >
      <div
        class="bg-primary text-primary-ink flex items-center gap-2 rounded-full px-4 py-2 text-sm font-medium shadow-lg"
      >
        <template v-if="isProcessing">
          Syncing {{ pendingCount }} change{{ pendingCount === 1 ? '' : 's' }}…
        </template>
        <template v-else>
          {{ pendingCount }} pending change{{ pendingCount === 1 ? '' : 's' }}
        </template>
      </div>
    </div>
  </Transition>
</template>
