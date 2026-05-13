<script setup lang="ts">
import { computed, onMounted, onUnmounted, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  UserIcon,
  KeyIcon,
  BanknotesIcon,
  BellIcon,
  ChevronRightIcon,
  ChevronLeftIcon,
  Cog6ToothIcon,
} from '@heroicons/vue/24/outline'
import type { FunctionalComponent } from 'vue'
import PageHeader from '@/components/common/PageHeader.vue'

interface SettingsSection {
  name: string
  label: string
  to: string
  icon: FunctionalComponent
}

const sections: SettingsSection[] = [
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

const currentSection = computed(() =>
  sections.find((s) => s.name === route.name)
)

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
</script>

<template>
  <div>
    <!-- Mobile back link, only when viewing a section -->
    <RouterLink
      v-if="currentSection"
      to="/settings"
      class="mb-2 -ml-2 inline-flex items-center gap-1 rounded-md px-2 py-1 text-sm text-gray-600 hover:bg-gray-100 lg:hidden dark:text-stone-300 dark:hover:bg-white/5"
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
        <nav class="flex flex-col gap-0.5" aria-label="Settings sections">
          <RouterLink
            v-for="section in sections"
            :key="section.name"
            :to="section.to"
            :aria-current="route.name === section.name ? 'page' : undefined"
            class="group flex items-center gap-3 rounded-md px-3 py-3 text-base font-medium transition-colors lg:py-2 lg:text-sm"
            active-class="bg-amber-50 text-amber-700 dark:bg-amber-500/10 dark:text-amber-300"
            :class="
              route.name === section.name
                ? ''
                : 'text-gray-700 hover:bg-gray-100 hover:text-gray-900 dark:text-stone-300 dark:hover:bg-white/5 dark:hover:text-white'
            "
          >
            <component
              :is="section.icon"
              class="size-5 shrink-0"
              aria-hidden="true"
            />
            <span class="flex-1">{{ section.label }}</span>
            <ChevronRightIcon
              class="size-4 text-gray-400 lg:hidden dark:text-stone-500"
              aria-hidden="true"
            />
          </RouterLink>
        </nav>
      </aside>

      <!-- Content: always visible at lg+; on mobile, only when a section is selected -->
      <div :class="['min-w-0', currentSection ? 'block' : 'hidden lg:block']">
        <RouterView />
      </div>
    </div>
  </div>
</template>
