<script setup lang="ts">
import { computed } from 'vue'
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
} from '@heroicons/vue/24/outline'
import {
  useAuthStore,
  useWebSocketStore,
  useWorkspaceStore,
  useCommandQueueStore,
} from '@/stores'
import { useDarkMode } from '@/composables/useDarkMode'

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()
const wsStore = useWebSocketStore()
const workspaceStore = useWorkspaceStore()
const commandQueueStore = useCommandQueueStore()
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

const navigation = [
  { name: 'Dashboard', href: '/', routeName: 'home' },
  { name: 'Events', href: '/events', routeName: 'events' },
  { name: 'Users', href: '/users', routeName: 'users' },
]

const userNavigation = [
  { name: 'Your Profile', href: '/profile' },
  { name: 'Settings', href: '#' },
]

const currentRouteName = computed(() => route.name)

function isActive(routeName: string): boolean {
  return currentRouteName.value === routeName
}

async function handleSignOut() {
  await authStore.logout()
  router.push('/login')
}

function getInitials(email: string | undefined): string {
  if (!email) return '?'
  return email.charAt(0).toUpperCase()
}
</script>

<template>
  <!-- Loading screen while waiting for initial sync -->
  <div
    v-if="!hasSynced && !hasCachedData"
    class="flex min-h-screen flex-col items-center justify-center bg-gray-50 dark:bg-gray-900"
  >
    <div class="text-center">
      <div
        class="inline-block h-12 w-12 animate-spin rounded-full border-4 border-rose-600 border-t-transparent"
      />
      <p class="mt-4 text-lg font-medium text-gray-700 dark:text-gray-300">
        Loading...
      </p>
    </div>
  </div>

  <div v-else class="min-h-full">
    <Disclosure
      v-slot="{ open, close }"
      as="nav"
      class="bg-rose-600 dark:bg-rose-800"
    >
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div class="flex h-16 items-center justify-between">
          <div class="flex items-center">
            <div class="shrink-0">
              <!-- Single workspace: just show name -->
              <span
                v-if="otherWorkspaces.length === 0"
                class="text-xl font-bold text-white"
              >
                {{ currentWorkspace?.name ?? 'Tayaway' }}
              </span>
              <!-- Multiple workspaces: dropdown -->
              <Menu v-else as="div" class="relative">
                <MenuButton
                  class="flex items-center gap-1 text-xl font-bold text-white hover:text-rose-100 focus:outline-hidden"
                >
                  {{ currentWorkspace?.name ?? 'Tayaway' }}
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
                    class="absolute left-0 z-10 mt-2 w-56 origin-top-left rounded-md bg-white py-1 shadow-lg ring-1 ring-black/5 focus:outline-hidden dark:bg-gray-800"
                  >
                    <MenuItem
                      v-for="ws in otherWorkspaces"
                      :key="ws.id"
                      v-slot="{ active }"
                    >
                      <button
                        type="button"
                        :class="[
                          active ? 'bg-gray-100 dark:bg-gray-700' : '',
                          'block w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-gray-300',
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
            <div class="hidden md:block">
              <div class="ml-10 flex items-baseline space-x-4">
                <router-link
                  v-for="item in navigation"
                  :key="item.name"
                  :to="item.href"
                  :class="[
                    isActive(item.routeName)
                      ? 'bg-rose-700 text-white dark:bg-rose-900'
                      : 'hover:bg-opacity-75 text-white hover:bg-rose-500 dark:hover:bg-rose-700',
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
                class="relative rounded-full bg-rose-600 p-1 text-rose-200 hover:text-white focus:ring-2 focus:ring-white focus:ring-offset-2 focus:ring-offset-rose-600 focus:outline-hidden dark:bg-rose-800"
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
                    class="relative flex max-w-xs items-center rounded-full bg-rose-600 text-sm focus:ring-2 focus:ring-white focus:ring-offset-2 focus:ring-offset-rose-600 focus:outline-hidden dark:bg-rose-800"
                  >
                    <span class="sr-only">Open user menu</span>
                    <span
                      class="inline-flex size-8 items-center justify-center rounded-full bg-rose-500 dark:bg-rose-700"
                    >
                      <span
                        data-testid="user-initial"
                        class="text-sm font-medium text-white"
                        >{{ getInitials(user?.email) }}</span
                      >
                    </span>
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
                    class="absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white py-1 shadow-lg ring-1 ring-black/5 focus:outline-hidden dark:bg-gray-800"
                  >
                    <div
                      class="border-b border-gray-200 px-4 py-2 text-sm text-gray-700 dark:border-gray-700 dark:text-gray-300"
                    >
                      {{ user?.email }}
                    </div>
                    <MenuItem
                      v-for="item in userNavigation"
                      :key="item.name"
                      v-slot="{ active, close }"
                    >
                      <router-link
                        :to="item.href"
                        :class="[
                          active ? 'bg-gray-100 dark:bg-gray-700' : '',
                          'block px-4 py-2 text-sm text-gray-700 dark:text-gray-300',
                        ]"
                        @click="close"
                      >
                        {{ item.name }}
                      </router-link>
                    </MenuItem>
                    <MenuItem v-slot="{ active }">
                      <button
                        type="button"
                        data-testid="sign-out-button"
                        :class="[
                          active ? 'bg-gray-100 dark:bg-gray-700' : '',
                          'block w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-gray-300',
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
              class="group hover:bg-opacity-75 relative inline-flex items-center justify-center rounded-md bg-rose-600 p-2 text-rose-200 hover:bg-rose-500 hover:text-white focus:ring-2 focus:ring-white focus:ring-offset-2 focus:ring-offset-rose-600 focus:outline-hidden dark:bg-rose-800 dark:hover:bg-rose-700"
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
          class="border-b border-rose-700 px-3 pt-2 pb-3 dark:border-rose-900"
        >
          <p
            class="px-2 text-xs font-semibold tracking-wide text-rose-200 uppercase"
          >
            Switch workspace
          </p>
          <button
            v-for="ws in otherWorkspaces"
            :key="ws.id"
            type="button"
            class="hover:bg-opacity-75 mt-1 block w-full rounded-md px-3 py-2 text-left text-base font-medium text-white hover:bg-rose-500 dark:hover:bg-rose-700"
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
                ? 'bg-rose-700 text-white dark:bg-rose-900'
                : 'hover:bg-opacity-75 text-white hover:bg-rose-500 dark:hover:bg-rose-700',
              'block rounded-md px-3 py-2 text-base font-medium',
            ]"
            :aria-current="isActive(item.routeName) ? 'page' : undefined"
            @click="close"
          >
            {{ item.name }}
          </router-link>
        </div>
        <div class="border-t border-rose-700 pt-4 pb-3 dark:border-rose-900">
          <div class="flex items-center px-5">
            <div class="shrink-0">
              <span
                class="inline-flex size-10 items-center justify-center rounded-full bg-rose-500 dark:bg-rose-700"
              >
                <span class="text-sm font-medium text-white">{{
                  getInitials(user?.email)
                }}</span>
              </span>
            </div>
            <div class="ml-3">
              <div class="text-base font-medium text-white">
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
              class="shrink-0 rounded-full bg-rose-600 p-1 text-rose-200 hover:text-white focus:ring-2 focus:ring-white focus:ring-offset-2 focus:ring-offset-rose-600 focus:outline-hidden dark:bg-rose-800"
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
              class="hover:bg-opacity-75 block rounded-md px-3 py-2 text-base font-medium text-white hover:bg-rose-500 dark:hover:bg-rose-700"
              @click="close"
            >
              {{ item.name }}
            </router-link>
            <button
              type="button"
              class="hover:bg-opacity-75 block w-full rounded-md px-3 py-2 text-left text-base font-medium text-white hover:bg-rose-500 dark:hover:bg-rose-700"
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

    <header v-if="$slots.header" class="bg-white shadow dark:bg-gray-800">
      <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <slot name="header" />
      </div>
    </header>
    <main>
      <div class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8">
        <RouterView />
      </div>
    </main>
  </div>

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
      v-if="pendingCount > 0 && !isOnline"
      class="fixed bottom-6 left-1/2 z-50 -translate-x-1/2"
    >
      <div
        class="flex items-center gap-2 rounded-full bg-amber-600 px-4 py-2 text-sm font-medium text-white shadow-lg dark:bg-amber-700"
      >
        {{ pendingCount }} pending change{{ pendingCount === 1 ? '' : 's' }}
      </div>
    </div>
  </Transition>
</template>
