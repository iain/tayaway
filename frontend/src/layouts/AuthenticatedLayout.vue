<script setup lang="ts">
import { computed, watchEffect } from 'vue'
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
} from '@heroicons/vue/24/outline'
import {
  useAuthStore,
  useWebSocketStore,
  useWorkspaceStore,
  useCommandQueueStore,
} from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useDarkMode } from '@/composables/useDarkMode'
import { getInitials } from '@/utils/member'
import AppAvatar from '@/components/common/AppAvatar.vue'
import CommandPalette from '@/components/common/CommandPalette.vue'
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
const { state: wsState, hasSynced, hasCachedData } = storeToRefs(wsStore)
const { pendingCount, isOnline } = storeToRefs(commandQueueStore)

const showConnectionBadge = computed(() => wsState.value !== 'authenticated')
const { currentWorkspace, otherWorkspaces } = storeToRefs(workspaceStore)

function handleSwitchWorkspace(workspaceId: string) {
  workspaceStore.switchWorkspace(workspaceId)
  wsStore.sendSwitchWorkspace(workspaceId)
}
const { isDark, toggle: toggleDarkMode } = useDarkMode()
const { open: openCommandPalette } = useCommandPalette()

const navigation = [
  { name: 'Dashboard', href: '/', routeName: 'home' },
  { name: 'Events', href: '/events', routeName: 'events' },
  { name: 'Tasks', href: '/tasks', routeName: 'tasks' },
  { name: 'Members', href: '/members', routeName: 'members' },
]

const userNavigation = [
  { name: 'Your Profile', href: '/profile' },
  { name: 'Account', href: '/account' },
]

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
  profile: 'Profile',
  account: 'Account',
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
    v-if="!hasSynced && !hasCachedData"
    class="flex min-h-screen flex-col items-center justify-center bg-gray-50 dark:bg-stone-900"
  >
    <div class="text-center">
      <div
        class="inline-block h-12 w-12 animate-spin rounded-full border-4 border-amber-600 border-t-transparent"
      />
      <p class="mt-4 text-lg font-medium text-gray-700 dark:text-stone-300">
        Loading...
      </p>
    </div>
  </div>

  <div v-else class="min-h-full">
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
                class="text-nav-text text-xl font-bold"
              >
                {{ currentWorkspace?.name ?? 'Tayaway' }}
              </router-link>
              <!-- Multiple workspaces: name links to dashboard, chevron opens dropdown -->
              <div v-else class="relative flex items-center gap-0.5">
                <router-link to="/" class="text-nav-text text-xl font-bold">
                  {{ currentWorkspace?.name ?? 'Tayaway' }}
                </router-link>
                <Menu as="div" class="relative">
                  <MenuButton
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
                      class="absolute left-0 z-10 mt-2 w-56 origin-top-left rounded-md bg-white py-1 shadow-lg ring-1 ring-black/5 focus:outline-hidden dark:bg-stone-800"
                    >
                      <MenuItem
                        v-for="ws in otherWorkspaces"
                        :key="ws.id"
                        v-slot="{ active }"
                      >
                        <button
                          type="button"
                          :class="[
                            active ? 'bg-gray-100 dark:bg-stone-700' : '',
                            'block w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-stone-300',
                          ]"
                          @click="handleSwitchWorkspace(ws.id)"
                        >
                          {{ ws.name }}
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
                      : 'text-nav-text hover:bg-nav-hover hover:bg-opacity-75',
                    'rounded-md px-3 py-2 text-sm font-medium',
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
              <!-- Connection status badge -->
              <button
                v-if="showConnectionBadge"
                type="button"
                class="mr-3 inline-flex cursor-pointer items-center gap-1.5 rounded-full bg-gray-900/40 px-3 py-1 text-xs font-medium text-white transition-colors hover:bg-gray-900/60"
                title="Click to reconnect"
                @click="wsStore.reconnect()"
              >
                <template v-if="!isOnline">
                  <span class="inline-block size-2 rounded-full bg-gray-300" />
                  Offline
                </template>
                <template v-else>
                  <span class="inline-block size-2 rounded-full bg-amber-400" />
                  Server offline
                </template>
              </button>

              <!-- Dark mode toggle -->
              <button
                type="button"
                class="bg-nav text-nav-text-muted hover:text-nav-text focus:ring-offset-nav relative rounded-full p-1 focus:ring-2 focus:ring-white focus:ring-offset-2 focus:outline-hidden"
                @click="toggleDarkMode"
              >
                <span class="sr-only">Toggle dark mode</span>
                <SunIcon v-if="isDark" class="size-6" aria-hidden="true" />
                <MoonIcon v-else class="size-6" aria-hidden="true" />
              </button>

              <!-- Profile dropdown -->
              <Menu as="div" class="relative ml-3">
                <div>
                  <MenuButton
                    data-testid="user-menu-button"
                    class="bg-nav focus:ring-offset-nav relative flex max-w-xs items-center rounded-full text-sm focus:ring-2 focus:ring-white focus:ring-offset-2 focus:outline-hidden"
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
                    class="absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white py-1 shadow-lg ring-1 ring-black/5 focus:outline-hidden dark:bg-stone-800"
                  >
                    <div
                      class="border-b border-gray-200 px-4 py-2 text-sm text-gray-700 dark:border-stone-700 dark:text-stone-300"
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
                          active ? 'bg-gray-100 dark:bg-stone-700' : '',
                          'block w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-stone-300',
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
                        data-testid="sign-out-button"
                        :class="[
                          active ? 'bg-gray-100 dark:bg-stone-700' : '',
                          'block w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-stone-300',
                        ]"
                        @click="handleSignOut"
                      >
                        Sign out
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
              class="group bg-nav text-nav-text-muted hover:bg-nav-hover hover:bg-opacity-75 hover:text-nav-text focus:ring-offset-nav relative inline-flex items-center justify-center rounded-md p-2 focus:ring-2 focus:ring-white focus:ring-offset-2 focus:outline-hidden"
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
            class="text-nav-text hover:bg-nav-hover hover:bg-opacity-75 mt-1 block w-full rounded-md px-3 py-2 text-left text-base font-medium"
            @click="
              () => {
                close()
                handleSwitchWorkspace(ws.id)
              }
            "
          >
            {{ ws.name }}
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
                : 'text-nav-text hover:bg-nav-hover hover:bg-opacity-75',
              'block rounded-md px-3 py-2 text-base font-medium',
            ]"
            :aria-current="isActive(item.routeName) ? 'page' : undefined"
            @click="close"
          >
            {{ item.name }}
          </router-link>
          <button
            type="button"
            class="text-nav-text hover:bg-nav-hover hover:bg-opacity-75 flex w-full items-center gap-2 rounded-md px-3 py-2 text-base font-medium"
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
            <div class="ml-3">
              <div class="text-nav-text text-base font-medium">
                {{ user?.email }}
              </div>
            </div>
            <button
              v-if="showConnectionBadge"
              type="button"
              class="ml-auto inline-flex cursor-pointer items-center gap-1.5 rounded-full bg-gray-900/40 px-3 py-1 text-xs font-medium text-white transition-colors hover:bg-gray-900/60"
              title="Click to reconnect"
              @click="wsStore.reconnect()"
            >
              <template v-if="!isOnline">
                <span class="inline-block size-2 rounded-full bg-gray-300" />
                Offline
              </template>
              <template v-else>
                <span class="inline-block size-2 rounded-full bg-amber-400" />
                Server offline
              </template>
            </button>
            <button
              type="button"
              class="bg-nav text-nav-text-muted hover:text-nav-text focus:ring-offset-nav shrink-0 rounded-full p-1 focus:ring-2 focus:ring-white focus:ring-offset-2 focus:outline-hidden"
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
              class="text-nav-text hover:bg-nav-hover hover:bg-opacity-75 block rounded-md px-3 py-2 text-base font-medium"
              @click="close"
            >
              {{ item.name }}
            </router-link>
            <button
              type="button"
              class="text-nav-text hover:bg-nav-hover hover:bg-opacity-75 block w-full rounded-md px-3 py-2 text-left text-base font-medium"
              @click="
                () => {
                  close()
                  handleSignOut()
                }
              "
            >
              Sign out
            </button>
          </div>
        </div>
      </DisclosurePanel>
    </Disclosure>

    <header v-if="$slots.header" class="bg-white shadow dark:bg-stone-800">
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
      v-if="pendingCount > 0 && wsState !== 'authenticated'"
      class="fixed bottom-20 left-1/2 z-50 -translate-x-1/2"
    >
      <div
        class="flex items-center gap-2 rounded-full bg-amber-600 px-4 py-2 text-sm font-medium text-white shadow-lg dark:bg-amber-700"
      >
        {{ pendingCount }} pending change{{ pendingCount === 1 ? '' : 's' }}
      </div>
    </div>
  </Transition>
</template>
