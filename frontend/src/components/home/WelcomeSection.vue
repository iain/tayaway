<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import {
  CalendarDaysIcon,
  UserGroupIcon,
  ClipboardDocumentListIcon,
} from '@heroicons/vue/24/outline'
const props = defineProps<{
  workspaceName: string
  userName: string | null
  memberCount: number
  hasEvents: boolean
}>()

const emit = defineEmits<{
  createEvent: []
}>()

const router = useRouter()

const greeting = computed(() => {
  const name = props.userName?.split(' ')[0]
  return name ? `Welcome, ${name}` : 'Welcome to Tayaway'
})

function navigateToMembers(): void {
  router.push('/members')
}

function navigateToTasks(): void {
  router.push('/tasks')
}
</script>

<template>
  <div>
    <div class="mb-6">
      <h2
        class="text-xl font-semibold tracking-tight text-gray-900 dark:text-white"
      >
        {{ greeting }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-stone-400">
        Here's how to get started with {{ workspaceName }}.
      </p>
    </div>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <!-- Step 1: Create an event -->
      <button
        type="button"
        class="group cursor-pointer rounded-lg border border-gray-200 p-4 text-left transition-colors hover:border-amber-300 hover:bg-amber-50 dark:border-stone-700 dark:hover:border-amber-700 dark:hover:bg-amber-900/10"
        @click="emit('createEvent')"
      >
        <CalendarDaysIcon
          class="mb-3 size-8 text-amber-600 dark:text-amber-400"
        />
        <h3 class="text-sm font-semibold text-gray-900 dark:text-white">
          Create an event
        </h3>
        <p class="mt-1 text-xs text-gray-500 dark:text-stone-400">
          Plan a trip, party, or activity. Add dates and let everyone vote.
        </p>
      </button>

      <!-- Step 2: Invite people -->
      <button
        type="button"
        class="group cursor-pointer rounded-lg border border-gray-200 p-4 text-left transition-colors hover:border-amber-300 hover:bg-amber-50 dark:border-stone-700 dark:hover:border-amber-700 dark:hover:bg-amber-900/10"
        @click="navigateToMembers"
      >
        <UserGroupIcon class="mb-3 size-8 text-amber-600 dark:text-amber-400" />
        <h3 class="text-sm font-semibold text-gray-900 dark:text-white">
          Invite your group
        </h3>
        <p class="mt-1 text-xs text-gray-500 dark:text-stone-400">
          {{
            memberCount <= 1
              ? 'Add friends so they can vote on dates and split costs.'
              : `${memberCount} members so far. Invite more to get everyone on board.`
          }}
        </p>
      </button>

      <!-- Step 3: Shared tasks -->
      <button
        type="button"
        class="group cursor-pointer rounded-lg border border-gray-200 p-4 text-left transition-colors hover:border-amber-300 hover:bg-amber-50 dark:border-stone-700 dark:hover:border-amber-700 dark:hover:bg-amber-900/10"
        @click="navigateToTasks"
      >
        <ClipboardDocumentListIcon
          class="mb-3 size-8 text-amber-600 dark:text-amber-400"
        />
        <h3 class="text-sm font-semibold text-gray-900 dark:text-white">
          Create a task list
        </h3>
        <p class="mt-1 text-xs text-gray-500 dark:text-stone-400">
          Keep track of what needs doing — packing lists, shopping, logistics.
        </p>
      </button>
    </div>
  </div>
</template>
