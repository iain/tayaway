<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { MagnifyingGlassIcon } from '@heroicons/vue/20/solid'
import {
  ArrowPathIcon,
  ArrowRightOnRectangleIcon,
  ArrowsRightLeftIcon,
  BanknotesIcon,
  BellIcon,
  CalendarDaysIcon,
  CheckCircleIcon,
  ClipboardDocumentListIcon,
  ClipboardIcon,
  Cog6ToothIcon,
  DocumentMagnifyingGlassIcon,
  HomeIcon,
  KeyIcon,
  MoonIcon,
  PlusIcon,
  ScaleIcon,
  SignalIcon,
  SunIcon,
  UserCircleIcon,
  UserGroupIcon,
  UserIcon,
} from '@heroicons/vue/24/outline'
import * as poolDb from '@/api/poolDb'
import {
  Combobox,
  ComboboxInput,
  ComboboxOption,
  ComboboxOptions,
  Dialog,
  DialogPanel,
  TransitionChild,
  TransitionRoot,
} from '@headlessui/vue'
import {
  useAuthStore,
  useObjectPoolStore,
  useWebSocketStore,
  useWorkspaceStore,
} from '@/stores'
import { useDarkMode } from '@/composables/useDarkMode'
import { useTaskActions } from '@/composables/useTaskActions'
import { useCommandPalette } from '@/composables/useCommandPalette'
import { can } from '@/composables/usePermission'

interface NavAction {
  type: 'action'
  id: string
  name: string
  icon: unknown
  href?: string
  run?: () => void | Promise<void>
}

interface EventResult {
  type: 'event'
  id: string
  name: string
}

interface TaskListResult {
  type: 'taskList'
  id: string
  name: string
}

interface TaskItemResult {
  type: 'taskItem'
  id: string
  name: string
  listName: string
}

type CommandItem = NavAction | EventResult | TaskListResult | TaskItemResult

const router = useRouter()
const pool = useObjectPoolStore()
const authStore = useAuthStore()
const wsStore = useWebSocketStore()
const workspaceStore = useWorkspaceStore()
const { isDark, toggle: toggleDarkMode } = useDarkMode()
const { triggerNewList } = useTaskActions()
const { isOpen: open, contextGroups } = useCommandPalette()

async function resetLocalCache(): Promise<void> {
  await poolDb.clearAll()
  window.location.reload()
}

async function logout(): Promise<void> {
  await authStore.logout()
  router.push('/login')
}

const workspaceSwitchActions = computed<NavAction[]>(() =>
  workspaceStore.otherWorkspaces.map((ws) => ({
    type: 'action' as const,
    id: `switch-workspace-${ws.id}`,
    name: `Switch to ${ws.name}`,
    icon: ArrowsRightLeftIcon,
    run: () => workspaceStore.switchWorkspace(ws.id),
  }))
)

// One per workspace you administer, like the settings sidebar — that page is
// where you go to sort out a workspace, including one you aren't currently in,
// so a single "Workspace settings" entry would have to guess which.
const workspaceSettingsActions = computed<NavAction[]>(() =>
  workspaceStore.administeredWorkspaces.map((ws) => ({
    type: 'action' as const,
    id: `settings-workspace-${ws.id}`,
    name: `${ws.name} settings`,
    icon: Cog6ToothIcon,
    href: `/settings/workspaces/${ws.id}/general`,
  }))
)

const quickActions = computed<NavAction[]>(() => [
  ...workspaceSwitchActions.value,
  { type: 'action', id: 'home', name: 'Dashboard', icon: HomeIcon, href: '/' },
  {
    type: 'action',
    id: 'events',
    name: 'Events',
    icon: CalendarDaysIcon,
    href: '/events',
  },
  {
    type: 'action',
    id: 'chores',
    name: 'Chores',
    icon: ClipboardDocumentListIcon,
    href: '/chores',
  },
  {
    type: 'action',
    id: 'new-event',
    name: 'New event',
    icon: PlusIcon,
    href: '/events/new',
  },
  {
    type: 'action',
    id: 'tasks',
    name: 'Tasks',
    icon: ClipboardDocumentListIcon,
    href: '/tasks',
  },
  {
    type: 'action',
    id: 'settle-up',
    name: 'Settle up',
    icon: ScaleIcon,
    href: '/settle-up',
  },
  {
    type: 'action',
    id: 'members',
    name: 'Members',
    icon: UserGroupIcon,
    href: '/members',
  },
  // Owner-only, like the nav item — the palette must not advertise a page
  // the backend would refuse.
  ...(can(workspaceStore.currentWorkspace?.permissions, 'view_audit_log')
    ? [
        {
          type: 'action' as const,
          id: 'audit-log',
          name: 'Audit log',
          icon: DocumentMagnifyingGlassIcon,
          href: '/audit-log',
        },
      ]
    : []),
  {
    type: 'action',
    id: 'settings',
    name: 'Settings',
    icon: UserCircleIcon,
    href: '/settings',
  },
  {
    type: 'action',
    id: 'settings-profile',
    name: 'Profile',
    icon: UserIcon,
    href: '/settings/profile',
  },
  {
    type: 'action',
    id: 'settings-login',
    name: 'Login',
    icon: KeyIcon,
    href: '/settings/login',
  },
  {
    type: 'action',
    id: 'settings-payment',
    name: 'Payment',
    icon: BanknotesIcon,
    href: '/settings/payment',
  },
  {
    type: 'action',
    id: 'settings-notifications',
    name: 'Notifications',
    icon: BellIcon,
    href: '/settings/notifications',
  },
  ...workspaceSettingsActions.value,
  {
    type: 'action',
    id: 'new-task-list',
    name: 'New task list',
    icon: PlusIcon,
    run: async () => {
      if (router.currentRoute.value.path !== '/tasks') {
        await router.push('/tasks')
      }
      triggerNewList()
    },
  },
  {
    type: 'action',
    id: 'dark-mode',
    name: isDark.value ? 'Switch to light mode' : 'Switch to dark mode',
    icon: isDark.value ? SunIcon : MoonIcon,
    run: toggleDarkMode,
  },
  ...(wsStore.gitSha
    ? [
        {
          type: 'action' as const,
          id: 'copy-revision',
          name: `Copy revision (${wsStore.gitSha.slice(0, 7)})`,
          icon: ClipboardIcon,
          run: () => navigator.clipboard.writeText(wsStore.gitSha!),
        },
      ]
    : []),
  {
    type: 'action',
    id: 'reconnect',
    name: 'Reconnect to server',
    icon: SignalIcon,
    run: () => wsStore.reconnect(),
  },
  {
    type: 'action',
    id: 'reset-cache',
    name: 'Reset local cache and reload',
    icon: ArrowPathIcon,
    run: resetLocalCache,
  },
  {
    type: 'action',
    id: 'logout',
    name: 'Log out',
    icon: ArrowRightOnRectangleIcon,
    run: logout,
  },
])

const query = ref('')

const filteredEvents = computed<EventResult[]>(() => {
  if (!query.value) return []
  const q = query.value.toLowerCase()
  return pool
    .getAll('event')
    .filter((e) => e.name.toLowerCase().includes(q))
    .map((e) => ({ type: 'event' as const, id: e.id, name: e.name }))
})

// Build workspace task list index once, shared by both task list and task item filters
const workspaceTaskLists = computed(() => {
  const wsId = workspaceStore.currentWorkspaceId
  return pool.getAll('taskList').filter((tl) => tl.workspaceId === wsId)
})

const filteredTaskLists = computed<TaskListResult[]>(() => {
  if (!query.value) return []
  const q = query.value.toLowerCase()
  return workspaceTaskLists.value
    .filter((tl) => tl.name.toLowerCase().includes(q))
    .map((tl) => ({ type: 'taskList' as const, id: tl.id, name: tl.name }))
})

const filteredTaskItems = computed<TaskItemResult[]>(() => {
  if (!query.value) return []
  const q = query.value.toLowerCase()
  const taskListNames = new Map(
    workspaceTaskLists.value.map((tl) => [tl.id, tl.name])
  )
  return pool
    .getAll('taskItem')
    .filter(
      (item) =>
        taskListNames.has(item.taskListId) &&
        item.completedAt === null &&
        item.content.toLowerCase().includes(q)
    )
    .map((item) => ({
      type: 'taskItem' as const,
      id: item.id,
      name: item.content,
      listName: taskListNames.get(item.taskListId) ?? '',
    }))
})

const filteredActions = computed<NavAction[]>(() => {
  if (!query.value) return []
  const q = query.value.toLowerCase()
  return quickActions.value.filter((a) => a.name.toLowerCase().includes(q))
})

const contextNavActions = computed(() => {
  const groups: { label: string; actions: NavAction[] }[] = []
  for (const [, group] of contextGroups.value) {
    groups.push({
      label: group.label,
      actions: group.actions.map((a) => ({
        type: 'action' as const,
        id: a.id,
        name: a.name,
        icon: a.icon,
        href: a.href,
        run: a.run,
      })),
    })
  }
  return groups
})

const filteredContextNavActions = computed(() => {
  if (!query.value) return []
  const q = query.value.toLowerCase()
  return contextNavActions.value
    .map((group) => ({
      label: group.label,
      actions: group.actions.filter((a) => a.name.toLowerCase().includes(q)),
    }))
    .filter((group) => group.actions.length > 0)
})

const hasResults = computed(
  () =>
    filteredEvents.value.length > 0 ||
    filteredTaskLists.value.length > 0 ||
    filteredTaskItems.value.length > 0 ||
    filteredActions.value.length > 0 ||
    filteredContextNavActions.value.length > 0
)

function onSelect(item: CommandItem | null) {
  if (!item) return
  open.value = false
  if (item.type === 'action') {
    if (item.run) {
      void item.run()
    } else if (item.href) {
      router.push(item.href)
    }
  } else if (item.type === 'event') {
    router.push(`/events/${item.id}`)
  } else {
    router.push('/tasks')
  }
}

function handleKeydown(e: KeyboardEvent) {
  if (e.key === 'k' && (e.metaKey || e.ctrlKey)) {
    e.preventDefault()
    open.value = !open.value
  }
}

onMounted(() => window.addEventListener('keydown', handleKeydown))
onUnmounted(() => window.removeEventListener('keydown', handleKeydown))
</script>

<template>
  <TransitionRoot :show="open" as="template" appear @after-leave="query = ''">
    <Dialog class="relative z-50" @close="open = false">
      <TransitionChild
        as="template"
        enter="ease-out duration-200"
        enter-from="opacity-0"
        enter-to="opacity-100"
        leave="ease-in duration-150"
        leave-from="opacity-100"
        leave-to="opacity-0"
      >
        <div
          class="fixed inset-0 bg-gray-500/50 transition-opacity dark:bg-stone-950/70"
        />
      </TransitionChild>

      <div
        class="fixed inset-0 z-10 w-screen overflow-y-auto p-4 sm:p-6 md:p-20"
      >
        <TransitionChild
          as="template"
          enter="ease-out duration-200"
          enter-from="opacity-0 scale-95"
          enter-to="opacity-100 scale-100"
          leave="ease-in duration-150"
          leave-from="opacity-100 scale-100"
          leave-to="opacity-0 scale-95"
        >
          <DialogPanel
            class="divide-line bg-surface ring-line mx-auto max-w-2xl transform divide-y overflow-hidden rounded-xl shadow-2xl ring-1 transition-all"
          >
            <Combobox @update:model-value="onSelect">
              <div class="grid grid-cols-1">
                <ComboboxInput
                  class="text-ink placeholder:text-ink-placeholder col-start-1 row-start-1 h-12 w-full bg-transparent pr-4 pl-11 text-base outline-hidden sm:text-sm"
                  placeholder="Search..."
                  @change="query = ($event.target as HTMLInputElement).value"
                />
                <MagnifyingGlassIcon
                  class="text-ink-muted pointer-events-none col-start-1 row-start-1 ml-4 size-5 self-center"
                  aria-hidden="true"
                />
              </div>

              <ComboboxOptions
                v-if="query === '' || hasResults"
                static
                as="ul"
                class="divide-line-faint max-h-80 scroll-py-2 divide-y overflow-y-auto"
              >
                <!-- Context groups (shown when query is empty) -->
                <template v-if="query === ''">
                  <li
                    v-for="group in contextNavActions"
                    :key="group.label"
                    class="p-2"
                  >
                    <h2 class="text-ink-muted mb-2 px-3 text-xs font-semibold">
                      {{ group.label }}
                    </h2>
                    <ul class="text-ink-muted text-sm">
                      <ComboboxOption
                        v-for="action in group.actions"
                        :key="action.id"
                        v-slot="{ active }"
                        :value="action"
                        as="template"
                      >
                        <li
                          :class="[
                            'flex cursor-default items-center rounded-md px-3 py-2 select-none',
                            active &&
                              'bg-amber-500 text-white dark:bg-amber-600',
                          ]"
                        >
                          <component
                            :is="action.icon"
                            :class="[
                              'size-5 flex-none',
                              active ? 'text-white' : 'text-ink-muted',
                            ]"
                            aria-hidden="true"
                          />
                          <span class="ml-3 flex-auto truncate">{{
                            action.name
                          }}</span>
                        </li>
                      </ComboboxOption>
                    </ul>
                  </li>
                </template>

                <!-- Navigation (shown when query is empty) -->
                <li v-if="query === ''" class="p-2">
                  <h2 class="text-ink-muted mb-2 px-3 text-xs font-semibold">
                    Navigation
                  </h2>
                  <ul class="text-ink-muted text-sm">
                    <ComboboxOption
                      v-for="action in quickActions"
                      :key="action.id"
                      v-slot="{ active }"
                      :value="action"
                      as="template"
                    >
                      <li
                        :class="[
                          'flex cursor-default items-center rounded-md px-3 py-2 select-none',
                          active && 'bg-amber-500 text-white dark:bg-amber-600',
                        ]"
                      >
                        <component
                          :is="action.icon"
                          :class="[
                            'size-5 flex-none',
                            active ? 'text-white' : 'text-ink-muted',
                          ]"
                          aria-hidden="true"
                        />
                        <span class="ml-3 flex-auto truncate">{{
                          action.name
                        }}</span>
                      </li>
                    </ComboboxOption>
                  </ul>
                </li>

                <!-- Search results -->
                <template v-if="query !== ''">
                  <li
                    v-for="group in filteredContextNavActions"
                    :key="group.label"
                    class="p-2"
                  >
                    <h2 class="text-ink-muted mb-2 px-3 text-xs font-semibold">
                      {{ group.label }}
                    </h2>
                    <ul class="text-ink-muted text-sm">
                      <ComboboxOption
                        v-for="action in group.actions"
                        :key="action.id"
                        v-slot="{ active }"
                        :value="action"
                        as="template"
                      >
                        <li
                          :class="[
                            'flex cursor-default items-center rounded-md px-3 py-2 select-none',
                            active &&
                              'bg-amber-500 text-white dark:bg-amber-600',
                          ]"
                        >
                          <component
                            :is="action.icon"
                            :class="[
                              'size-5 flex-none',
                              active ? 'text-white' : 'text-ink-muted',
                            ]"
                            aria-hidden="true"
                          />
                          <span class="ml-3 flex-auto truncate">{{
                            action.name
                          }}</span>
                        </li>
                      </ComboboxOption>
                    </ul>
                  </li>

                  <li v-if="filteredEvents.length > 0" class="p-2">
                    <h2 class="text-ink-muted mb-2 px-3 text-xs font-semibold">
                      Events
                    </h2>
                    <ul class="text-ink-muted text-sm">
                      <ComboboxOption
                        v-for="event in filteredEvents"
                        :key="event.id"
                        v-slot="{ active }"
                        :value="event"
                        as="template"
                      >
                        <li
                          :class="[
                            'flex cursor-default items-center rounded-md px-3 py-2 select-none',
                            active &&
                              'bg-amber-500 text-white dark:bg-amber-600',
                          ]"
                        >
                          <CalendarDaysIcon
                            :class="[
                              'size-5 flex-none',
                              active ? 'text-white' : 'text-ink-muted',
                            ]"
                            aria-hidden="true"
                          />
                          <span class="ml-3 flex-auto truncate">{{
                            event.name
                          }}</span>
                          <span
                            v-if="active"
                            :class="[
                              'ml-3 flex-none text-xs',
                              active ? 'text-amber-100' : 'text-ink-muted',
                            ]"
                          >
                            Jump to...
                          </span>
                        </li>
                      </ComboboxOption>
                    </ul>
                  </li>

                  <li v-if="filteredTaskLists.length > 0" class="p-2">
                    <h2 class="text-ink-muted mb-2 px-3 text-xs font-semibold">
                      Task Lists
                    </h2>
                    <ul class="text-ink-muted text-sm">
                      <ComboboxOption
                        v-for="list in filteredTaskLists"
                        :key="list.id"
                        v-slot="{ active }"
                        :value="list"
                        as="template"
                      >
                        <li
                          :class="[
                            'flex cursor-default items-center rounded-md px-3 py-2 select-none',
                            active &&
                              'bg-amber-500 text-white dark:bg-amber-600',
                          ]"
                        >
                          <ClipboardDocumentListIcon
                            :class="[
                              'size-5 flex-none',
                              active ? 'text-white' : 'text-ink-muted',
                            ]"
                            aria-hidden="true"
                          />
                          <span class="ml-3 flex-auto truncate">{{
                            list.name
                          }}</span>
                          <span
                            v-if="active"
                            class="ml-3 flex-none text-xs text-amber-100"
                          >
                            Jump to...
                          </span>
                        </li>
                      </ComboboxOption>
                    </ul>
                  </li>

                  <li v-if="filteredTaskItems.length > 0" class="p-2">
                    <h2 class="text-ink-muted mb-2 px-3 text-xs font-semibold">
                      Task Items
                    </h2>
                    <ul class="text-ink-muted text-sm">
                      <ComboboxOption
                        v-for="item in filteredTaskItems"
                        :key="item.id"
                        v-slot="{ active }"
                        :value="item"
                        as="template"
                      >
                        <li
                          :class="[
                            'flex cursor-default items-center rounded-md px-3 py-2 select-none',
                            active &&
                              'bg-amber-500 text-white dark:bg-amber-600',
                          ]"
                        >
                          <CheckCircleIcon
                            :class="[
                              'size-5 flex-none',
                              active ? 'text-white' : 'text-ink-muted',
                            ]"
                            aria-hidden="true"
                          />
                          <span class="ml-3 flex-auto truncate">{{
                            item.name
                          }}</span>
                          <span
                            :class="[
                              'ml-3 flex-none truncate text-xs',
                              active ? 'text-amber-100' : 'text-ink-muted',
                            ]"
                          >
                            {{ item.listName }}
                          </span>
                        </li>
                      </ComboboxOption>
                    </ul>
                  </li>

                  <li v-if="filteredActions.length > 0" class="p-2">
                    <h2 class="text-ink-muted mb-2 px-3 text-xs font-semibold">
                      Navigation
                    </h2>
                    <ul class="text-ink-muted text-sm">
                      <ComboboxOption
                        v-for="action in filteredActions"
                        :key="action.id"
                        v-slot="{ active }"
                        :value="action"
                        as="template"
                      >
                        <li
                          :class="[
                            'flex cursor-default items-center rounded-md px-3 py-2 select-none',
                            active &&
                              'bg-amber-500 text-white dark:bg-amber-600',
                          ]"
                        >
                          <component
                            :is="action.icon"
                            :class="[
                              'size-5 flex-none',
                              active ? 'text-white' : 'text-ink-muted',
                            ]"
                            aria-hidden="true"
                          />
                          <span class="ml-3 flex-auto truncate">{{
                            action.name
                          }}</span>
                        </li>
                      </ComboboxOption>
                    </ul>
                  </li>
                </template>
              </ComboboxOptions>

              <div
                v-if="query !== '' && !hasResults"
                class="px-6 py-14 text-center sm:px-14"
              >
                <ClipboardDocumentListIcon
                  class="text-ink-muted mx-auto size-6"
                  aria-hidden="true"
                />
                <p class="text-ink-muted mt-4 text-sm">
                  No results for "{{ query }}". Try searching for an event,
                  task, or page name.
                </p>
              </div>
            </Combobox>
          </DialogPanel>
        </TransitionChild>
      </div>
    </Dialog>
  </TransitionRoot>
</template>
