<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { storeToRefs } from 'pinia'
import {
  UserIcon,
  KeyIcon,
  BanknotesIcon,
  BellIcon,
  ChevronRightIcon,
  ChevronLeftIcon,
  Cog6ToothIcon,
  PlusIcon,
} from '@heroicons/vue/24/outline'
import type { FunctionalComponent } from 'vue'
import PageHeader from '@/components/common/PageHeader.vue'
import NewWorkspaceModal from '@/components/workspace/NewWorkspaceModal.vue'
import { useWorkspaceStore } from '@/stores/workspace'

interface SettingsSection {
  name: string
  label: string
  to: string
  icon: FunctionalComponent
  workspaceId?: string
}

interface SettingsGroup {
  key: string
  label: string
  sections: SettingsSection[]
  workspaceId?: string
}

const personalSections: SettingsSection[] = [
  {
    name: 'settings-profile',
    label: 'Profile',
    to: '/settings/profile',
    icon: UserIcon,
  },
  {
    name: 'settings-login',
    label: 'Login',
    to: '/settings/login',
    icon: KeyIcon,
  },
  {
    name: 'settings-payment',
    label: 'Payment',
    to: '/settings/payment',
    icon: BanknotesIcon,
  },
  {
    name: 'settings-notifications',
    label: 'Notifications',
    to: '/settings/notifications',
    icon: BellIcon,
  },
]

const route = useRoute()
const router = useRouter()
const workspaceStore = useWorkspaceStore()
const { administeredWorkspaces } = storeToRefs(workspaceStore)

// Personal settings first, then one group per workspace you administer —
// every one of them, not just the active workspace. Settings is where you
// go to sort out a workspace you're not currently looking at.
const groups = computed<SettingsGroup[]>(() => [
  { key: 'personal', label: 'Personal', sections: personalSections },
  ...administeredWorkspaces.value.map((workspace) => ({
    key: `workspace-${workspace.id}`,
    label: workspace.name,
    workspaceId: workspace.id,
    sections: [
      {
        name: 'settings-workspace-general',
        label: 'General',
        to: `/settings/workspaces/${workspace.id}/general`,
        icon: Cog6ToothIcon,
        workspaceId: workspace.id,
      },
    ],
  })),
])

// Workspace sections all share one route name, so the active one is the
// section whose workspace id matches the route too.
function isActive(section: SettingsSection): boolean {
  if (route.name !== section.name) return false
  return (
    section.workspaceId === undefined || route.params.id === section.workspaceId
  )
}

const currentSection = computed(() =>
  groups.value.flatMap((group) => group.sections).find(isActive)
)

const newWorkspaceOpen = ref(false)

// Desktop expects a section to be selected; mobile uses /settings as a menu page.
const DESKTOP_QUERY = '(min-width: 1024px)'
let mq: MediaQueryList | null = null

function redirectIfDesktopIndex() {
  if (!mq?.matches) return
  if (route.name === 'settings') {
    router.replace('/settings/profile')
  }
}

onMounted(() => {
  mq = window.matchMedia(DESKTOP_QUERY)
  redirectIfDesktopIndex()
  mq.addEventListener('change', redirectIfDesktopIndex)
})

onUnmounted(() => {
  mq?.removeEventListener('change', redirectIfDesktopIndex)
})

watch(() => route.name, redirectIfDesktopIndex)

function onWorkspaceCreated(workspaceId: string): void {
  router.push(`/settings/workspaces/${workspaceId}/general`)
}
</script>

<template>
  <div>
    <!-- Mobile back link, only when viewing a section -->
    <RouterLink
      v-if="currentSection"
      to="/settings"
      class="text-ink-muted hover:bg-surface-sunken mb-2 -ml-2 inline-flex items-center gap-1 rounded-md px-2 py-1 text-sm lg:hidden"
    >
      <ChevronLeftIcon class="size-4" aria-hidden="true" />
      Settings
    </RouterLink>

    <PageHeader title="Settings" :icon="Cog6ToothIcon" />

    <div class="lg:grid lg:grid-cols-[16rem_1fr] lg:gap-10">
      <!-- Sidebar: always visible at lg+; on mobile, only when no section selected -->
      <aside
        :class="['mb-6 lg:mb-0', currentSection ? 'hidden lg:block' : 'block']"
      >
        <nav class="flex flex-col gap-6" aria-label="Settings sections">
          <div
            v-for="group in groups"
            :key="group.key"
            data-testid="settings-nav-group"
            :data-group="group.workspaceId ? 'workspace' : group.key"
            :data-workspace-id="group.workspaceId"
          >
            <h2
              class="text-ink-muted mb-1 px-3 text-xs font-semibold tracking-wide uppercase"
            >
              {{ group.label }}
            </h2>
            <div class="flex flex-col gap-0.5">
              <RouterLink
                v-for="section in group.sections"
                :key="section.to"
                :to="section.to"
                :aria-current="isActive(section) ? 'page' : undefined"
                class="group flex items-center gap-3 rounded-md px-3 py-3 text-base font-medium transition-colors lg:py-2 lg:text-sm"
                :class="
                  isActive(section)
                    ? 'bg-amber-50 text-amber-700 dark:bg-amber-500/10 dark:text-amber-300'
                    : 'text-ink hover:bg-surface-sunken'
                "
              >
                <component
                  :is="section.icon"
                  class="size-5 shrink-0"
                  aria-hidden="true"
                />
                <span class="flex-1">{{ section.label }}</span>
                <ChevronRightIcon
                  class="text-ink-muted size-4 lg:hidden"
                  aria-hidden="true"
                />
              </RouterLink>
            </div>
          </div>

          <button
            type="button"
            data-testid="settings-new-workspace"
            class="text-ink hover:bg-surface-sunken flex items-center gap-3 rounded-md px-3 py-3 text-base font-medium transition-colors lg:py-2 lg:text-sm"
            @click="newWorkspaceOpen = true"
          >
            <PlusIcon class="size-5 shrink-0" aria-hidden="true" />
            <span class="flex-1 text-left">New workspace</span>
          </button>
        </nav>
      </aside>

      <!-- Content: always visible at lg+; on mobile, only when a section is selected -->
      <div :class="['min-w-0', currentSection ? 'block' : 'hidden lg:block']">
        <RouterView />
      </div>
    </div>

    <!-- Mounted only while open. Pages elsewhere keep their modals mounted
         with :open, but this one lives in the layout: a closed dialog still
         contributes its fields to the DOM, and a permanent second "Name"
         input across every settings page is a trap for both assistive tech
         and tests. -->
    <NewWorkspaceModal
      v-if="newWorkspaceOpen"
      open
      @close="newWorkspaceOpen = false"
      @created="onWorkspaceCreated"
    />
  </div>
</template>
