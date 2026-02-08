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
} from '@heroicons/vue/24/outline'
import { useAuthStore, useWebSocketStore } from '@/stores'
import { useDarkMode } from '@/composables/useDarkMode'

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()
const wsStore = useWebSocketStore()
const { user } = storeToRefs(authStore)
const { hasSynced } = storeToRefs(wsStore)
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
    v-if="!hasSynced"
    class="min-h-screen flex flex-col items-center justify-center bg-gray-50 dark:bg-gray-900"
  >
    <div class="text-center">
      <div class="inline-block animate-spin rounded-full h-12 w-12 border-4 border-rose-600 border-t-transparent" />
      <p class="mt-4 text-lg font-medium text-gray-700 dark:text-gray-300">
        Loading...
      </p>
    </div>
  </div>

  <div
    v-else
    class="min-h-full"
  >
    <Disclosure
      v-slot="{ open, close }"
      as="nav"
      class="bg-rose-600 dark:bg-rose-800"
    >
      <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div class="flex h-16 items-center justify-between">
          <div class="flex items-center">
            <div class="shrink-0">
              <span class="text-white font-bold text-xl">Tayaway</span>
            </div>
            <div class="hidden md:block">
              <div class="ml-10 flex items-baseline space-x-4">
                <router-link
                  v-for="item in navigation"
                  :key="item.name"
                  :to="item.href"
                  :class="[
                    isActive(item.routeName)
                      ? 'bg-rose-700 dark:bg-rose-900 text-white'
                      : 'text-white hover:bg-rose-500 dark:hover:bg-rose-700 hover:bg-opacity-75',
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
              <!-- Dark mode toggle -->
              <button
                type="button"
                class="relative rounded-full bg-rose-600 dark:bg-rose-800 p-1 text-rose-200 hover:text-white focus:ring-2 focus:ring-white focus:ring-offset-2 focus:ring-offset-rose-600 focus:outline-hidden"
                @click="toggleDarkMode"
              >
                <span class="sr-only">Toggle dark mode</span>
                <SunIcon
                  v-if="isDark"
                  class="size-6"
                  aria-hidden="true"
                />
                <MoonIcon
                  v-else
                  class="size-6"
                  aria-hidden="true"
                />
              </button>

              <!-- Profile dropdown -->
              <Menu
                as="div"
                class="relative ml-3"
              >
                <div>
                  <MenuButton
                    data-testid="user-menu-button"
                    class="relative flex max-w-xs items-center rounded-full bg-rose-600 dark:bg-rose-800 text-sm focus:ring-2 focus:ring-white focus:ring-offset-2 focus:ring-offset-rose-600 focus:outline-hidden"
                  >
                    <span class="sr-only">Open user menu</span>
                    <span class="inline-flex size-8 items-center justify-center rounded-full bg-rose-500 dark:bg-rose-700">
                      <span
                        data-testid="user-initial"
                        class="text-sm font-medium text-white"
                      >{{ getInitials(user?.email) }}</span>
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
                  <MenuItems class="absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white dark:bg-gray-800 py-1 ring-1 shadow-lg ring-black/5 focus:outline-hidden">
                    <div class="px-4 py-2 text-sm text-gray-700 dark:text-gray-300 border-b border-gray-200 dark:border-gray-700">
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
                          'block w-full text-left px-4 py-2 text-sm text-gray-700 dark:text-gray-300',
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
            <DisclosureButton class="group relative inline-flex items-center justify-center rounded-md bg-rose-600 dark:bg-rose-800 p-2 text-rose-200 hover:bg-rose-500 dark:hover:bg-rose-700 hover:bg-opacity-75 hover:text-white focus:ring-2 focus:ring-white focus:ring-offset-2 focus:ring-offset-rose-600 focus:outline-hidden">
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
        <div class="space-y-1 px-2 pt-2 pb-3 sm:px-3">
          <router-link
            v-for="item in navigation"
            :key="item.name"
            :to="item.href"
            :class="[
              isActive(item.routeName)
                ? 'bg-rose-700 dark:bg-rose-900 text-white'
                : 'text-white hover:bg-rose-500 dark:hover:bg-rose-700 hover:bg-opacity-75',
              'block rounded-md px-3 py-2 text-base font-medium',
            ]"
            :aria-current="isActive(item.routeName) ? 'page' : undefined"
            @click="close"
          >
            {{ item.name }}
          </router-link>
        </div>
        <div class="border-t border-rose-700 dark:border-rose-900 pt-4 pb-3">
          <div class="flex items-center px-5">
            <div class="shrink-0">
              <span class="inline-flex size-10 items-center justify-center rounded-full bg-rose-500 dark:bg-rose-700">
                <span class="text-sm font-medium text-white">{{ getInitials(user?.email) }}</span>
              </span>
            </div>
            <div class="ml-3">
              <div class="text-base font-medium text-white">
                {{ user?.email }}
              </div>
            </div>
            <button
              type="button"
              class="relative ml-auto shrink-0 rounded-full bg-rose-600 dark:bg-rose-800 p-1 text-rose-200 hover:text-white focus:ring-2 focus:ring-white focus:ring-offset-2 focus:ring-offset-rose-600 focus:outline-hidden"
              @click="toggleDarkMode"
            >
              <span class="sr-only">Toggle dark mode</span>
              <SunIcon
                v-if="isDark"
                class="size-6"
                aria-hidden="true"
              />
              <MoonIcon
                v-else
                class="size-6"
                aria-hidden="true"
              />
            </button>
          </div>
          <div class="mt-3 space-y-1 px-2">
            <router-link
              v-for="item in userNavigation"
              :key="item.name"
              :to="item.href"
              class="block rounded-md px-3 py-2 text-base font-medium text-white hover:bg-rose-500 dark:hover:bg-rose-700 hover:bg-opacity-75"
              @click="close"
            >
              {{ item.name }}
            </router-link>
            <button
              type="button"
              class="block w-full text-left rounded-md px-3 py-2 text-base font-medium text-white hover:bg-rose-500 dark:hover:bg-rose-700 hover:bg-opacity-75"
              @click="close(); handleSignOut()"
            >
              Sign out
            </button>
          </div>
        </div>
      </DisclosurePanel>
    </Disclosure>

    <header
      v-if="$slots.header"
      class="bg-white dark:bg-gray-800 shadow"
    >
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
</template>
