<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import {
  ArrowRightIcon,
  CalendarDaysIcon,
  UserGroupIcon,
  ClipboardDocumentListIcon,
} from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'

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
    <!-- Greeting + primary CTA -->
    <div
      class="rounded-xl border border-amber-200 bg-amber-50/50 p-6 sm:p-8 dark:border-amber-800/40 dark:bg-amber-950/20"
    >
      <h2
        class="text-xl font-semibold tracking-tight text-gray-900 dark:text-white"
      >
        {{ greeting }}
      </h2>
      <p class="mt-1 text-sm text-gray-600 dark:text-stone-400">
        Start by creating an event — a trip, party, or anything your group is
        planning. From there you can vote on dates, split costs, and organise
        chores.
      </p>
      <AppButton class="mt-5" @click="emit('createEvent')">
        <CalendarDaysIcon class="size-5" />
        Create your first event
      </AppButton>
    </div>

    <!-- Secondary suggestions -->
    <div class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-6">
      <button
        type="button"
        class="group inline-flex cursor-pointer items-center gap-2 text-sm text-gray-600 transition-colors hover:text-amber-700 dark:text-stone-400 dark:hover:text-amber-400"
        @click="navigateToMembers"
      >
        <UserGroupIcon class="size-4 shrink-0" />
        <span>
          {{
            memberCount <= 1
              ? 'Invite your group'
              : `${memberCount} members — invite more`
          }}
        </span>
        <ArrowRightIcon
          class="size-3 shrink-0 opacity-0 transition-opacity group-hover:opacity-100"
        />
      </button>
      <button
        type="button"
        class="group inline-flex cursor-pointer items-center gap-2 text-sm text-gray-600 transition-colors hover:text-amber-700 dark:text-stone-400 dark:hover:text-amber-400"
        @click="navigateToTasks"
      >
        <ClipboardDocumentListIcon class="size-4 shrink-0" />
        <span>Create a shared task list</span>
        <ArrowRightIcon
          class="size-3 shrink-0 opacity-0 transition-opacity group-hover:opacity-100"
        />
      </button>
    </div>
  </div>
</template>
