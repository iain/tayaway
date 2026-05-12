<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useRouter } from 'vue-router'
import {
  Menu,
  MenuButton,
  MenuItems,
  MenuItem,
  Popover,
  PopoverButton,
  PopoverPanel,
} from '@headlessui/vue'
import { BellIcon, EllipsisHorizontalIcon } from '@heroicons/vue/24/outline'
import { useInboxStore } from '@/stores/inbox'
import type { InboxNotification } from '@/stores/inbox'
import EmptyState from '@/components/common/EmptyState.vue'
import { iconForKind } from '@/utils/notificationKind'

const inbox = useInboxStore()
const { notifications, unreadCount, loading } = storeToRefs(inbox)
const router = useRouter()

function handleVisibilityChange(): void {
  if (document.visibilityState === 'visible') {
    void inbox.load()
  }
}

onMounted(() => {
  void inbox.load()
  document.addEventListener('visibilitychange', handleVisibilityChange)
})

onUnmounted(() => {
  document.removeEventListener('visibilitychange', handleVisibilityChange)
})

function isInternalHref(href: string | undefined): href is string {
  if (!href) return false
  if (href.startsWith('/')) return true
  try {
    const url = new URL(href)
    return url.origin === window.location.origin
  } catch {
    return false
  }
}

function pathFromHref(href: string): string {
  if (href.startsWith('/')) return href
  try {
    const url = new URL(href)
    return url.pathname + url.search + url.hash
  } catch {
    return '/'
  }
}

async function activate(
  notification: InboxNotification,
  close: () => void
): Promise<void> {
  await inbox.markRead(notification.id)
  const href = notification.data.href
  if (isInternalHref(href)) {
    close()
    void router.push(pathFromHref(href))
  } else if (href) {
    close()
    window.open(href, '_blank', 'noopener')
  } else {
    close()
  }
}

function silence(notification: InboxNotification): void {
  inbox.silenceKind(
    notification.kind,
    "Won't send these anymore.",
    notification.id
  )
}

function relativeTime(iso: string): string {
  const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
  if (seconds < 60) return 'just now'
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 7) return `${days}d ago`
  return new Date(iso).toLocaleDateString()
}
</script>

<template>
  <Popover as="div" class="relative">
    <PopoverButton
      class="bg-nav text-nav-text-muted hover:text-nav-text relative rounded-full p-1 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
      aria-label="Notifications"
    >
      <BellIcon class="size-6" aria-hidden="true" />
      <span
        v-if="unreadCount > 0"
        class="absolute -top-0.5 -right-0.5 inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-rose-500 px-1 text-[10px] font-semibold text-white"
        :aria-label="`${unreadCount} unread`"
      >
        {{ unreadCount > 99 ? '99+' : unreadCount }}
      </span>
    </PopoverButton>

    <transition
      enter-active-class="transition ease-out duration-100"
      enter-from-class="transform opacity-0 scale-95"
      enter-to-class="transform opacity-100 scale-100"
      leave-active-class="transition ease-in duration-75"
      leave-from-class="transform opacity-100 scale-100"
      leave-to-class="transform opacity-0 scale-95"
    >
      <PopoverPanel
        v-slot="{ close }"
        class="absolute right-0 z-20 mt-2 w-80 origin-top-right overflow-hidden rounded-md bg-white shadow-lg ring-1 ring-black/5 focus:outline-hidden dark:bg-stone-800"
      >
        <div
          class="flex items-center justify-between border-b border-gray-200 px-4 py-2 dark:border-stone-700"
        >
          <span class="text-sm font-medium text-gray-900 dark:text-white">
            Notifications
          </span>
          <button
            v-if="unreadCount > 0"
            type="button"
            class="text-xs text-rose-600 hover:underline dark:text-rose-400"
            @click="inbox.markAllRead()"
          >
            Mark all read
          </button>
        </div>

        <div
          v-if="loading && notifications.length === 0"
          class="px-4 py-6 text-center text-sm text-gray-500 dark:text-stone-400"
        >
          Loading…
        </div>

        <div v-else-if="notifications.length === 0" class="px-4">
          <EmptyState
            :icon="BellIcon"
            heading="You’re all caught up."
            description="New events, settlements, and sign-ins will show up here."
          />
        </div>

        <ul v-else class="max-h-96 overflow-y-auto">
          <li
            v-for="notification in notifications"
            :key="notification.id"
            :class="[
              notification.readAt === null
                ? 'bg-rose-50/50 dark:bg-rose-500/5'
                : '',
              'group/row relative border-b border-gray-100 last:border-b-0 dark:border-stone-700',
            ]"
          >
            <button
              type="button"
              class="flex w-full items-start gap-3 px-4 py-3 pr-12 text-left hover:bg-gray-50 dark:hover:bg-stone-700"
              @click="activate(notification, close)"
            >
              <component
                :is="iconForKind(notification.kind)"
                class="mt-0.5 size-5 shrink-0 text-gray-400 dark:text-stone-500"
                aria-hidden="true"
              />
              <div class="min-w-0 flex-1">
                <div class="flex items-start justify-between gap-2">
                  <p class="text-sm font-medium text-gray-900 dark:text-white">
                    {{ notification.data.title ?? 'Notification' }}
                  </p>
                  <span
                    class="shrink-0 text-xs text-gray-400 dark:text-stone-500"
                  >
                    {{ relativeTime(notification.createdAt) }}
                  </span>
                </div>
                <p
                  v-if="notification.data.body"
                  class="mt-1 text-sm text-gray-600 dark:text-stone-400"
                >
                  {{ notification.data.body }}
                </p>
              </div>
            </button>

            <Menu as="div" class="absolute top-2 right-2">
              <MenuButton
                aria-label="More actions"
                class="flex size-8 cursor-pointer items-center justify-center rounded-md text-gray-400 transition-opacity hover:bg-black/5 hover:text-gray-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus max-md:opacity-100 md:opacity-0 md:group-focus-within/row:opacity-100 md:group-hover/row:opacity-100 dark:text-stone-500 dark:hover:bg-white/10 dark:hover:text-stone-300"
              >
                <EllipsisHorizontalIcon class="size-5" aria-hidden="true" />
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
                  class="absolute right-0 z-30 mt-1 w-52 origin-top-right rounded-md bg-white py-1 shadow-lg ring-1 ring-black/5 focus:outline-hidden dark:bg-stone-800"
                >
                  <MenuItem
                    v-if="notification.readAt === null"
                    v-slot="{ active }"
                  >
                    <button
                      type="button"
                      :class="[
                        active ? 'bg-gray-100 dark:bg-stone-700' : '',
                        'block w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-stone-300',
                      ]"
                      @click="inbox.markRead(notification.id)"
                    >
                      Mark as read
                    </button>
                  </MenuItem>
                  <MenuItem v-slot="{ active }">
                    <button
                      type="button"
                      :class="[
                        active ? 'bg-gray-100 dark:bg-stone-700' : '',
                        'block w-full px-4 py-2 text-left text-sm text-gray-700 dark:text-stone-300',
                      ]"
                      @click="silence(notification)"
                    >
                      Stop sending me these
                    </button>
                  </MenuItem>
                </MenuItems>
              </transition>
            </Menu>
          </li>
        </ul>
      </PopoverPanel>
    </transition>
  </Popover>
</template>
