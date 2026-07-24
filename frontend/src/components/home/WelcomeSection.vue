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
  // Where inviting actually happens, when this viewer may invite. Null sends
  // them to the directory instead, which is all they can do there.
  manageMembersLink: string | null
}>()

const emit = defineEmits<{
  createEvent: []
}>()

const router = useRouter()

const greeting = computed(() => {
  const name = props.userName?.split(' ')[0]
  return name ? `Welcome, ${name}` : 'Welcome to Tayaway'
})

// Don't promise an invitation to someone who can't send one.
const inviteLabel = computed(() => {
  if (!props.manageMembersLink) {
    return `${props.memberCount} members`
  } else if (props.memberCount <= 1) {
    return 'Invite your group'
  } else {
    return `${props.memberCount} members — invite more`
  }
})

function navigateToMembers(): void {
  router.push(props.manageMembersLink ?? '/members')
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
      <h2 class="text-ink text-xl font-semibold tracking-tight">
        {{ greeting }}
      </h2>
      <p class="text-ink-muted mt-1 text-sm">
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
        class="text-ink-muted group focus-visible:outline-focus inline-flex cursor-pointer items-center gap-2 rounded py-2 text-sm transition-colors hover:text-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 dark:hover:text-amber-400"
        @click="navigateToMembers"
      >
        <UserGroupIcon class="size-4 shrink-0" />
        <span>
          {{ inviteLabel }}
        </span>
        <ArrowRightIcon
          class="size-3 shrink-0 opacity-0 transition-opacity group-hover:opacity-100"
        />
      </button>
      <button
        type="button"
        class="text-ink-muted group focus-visible:outline-focus inline-flex cursor-pointer items-center gap-2 rounded py-2 text-sm transition-colors hover:text-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 dark:hover:text-amber-400"
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
