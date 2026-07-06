<script setup lang="ts">
import { computed } from 'vue'
import { PlusIcon } from '@heroicons/vue/24/outline'
import { ChatBubbleLeftIcon } from '@heroicons/vue/24/solid'
import PushPinIcon from '@/components/icons/PushPinIcon.vue'
import type { PoolChoreAssignment, PoolMember } from '@/types/pool'
import { getMemberNameFromMap } from '@/utils/member'

const props = defineProps<{
  assignments: PoolChoreAssignment[]
  peoplePerDay: number
  memberMap: Map<string, PoolMember>
  currentUserId: string | null
}>()

const emit = defineEmits<{
  assign: [anchorEl: HTMLElement]
  editAssignment: [assignment: PoolChoreAssignment, anchorEl: HTMLElement]
}>()

const hasEmptySlots = computed(
  () => props.assignments.length < props.peoplePerDay
)

function isCurrentUser(a: PoolChoreAssignment): boolean {
  return props.currentUserId !== null && a.userId === props.currentUserId
}

// The chip shows the name and dual-codes pinned/note state with icons; this
// folds the same information into one accessible name so screen-reader users
// hear what sighted users see (the note otherwise lived only in `title`).
// "you" is likewise dual-coded — the amber fill that marks your own chips is
// invisible to a screen reader without it.
function chipLabel(a: PoolChoreAssignment): string {
  const parts = [getMemberNameFromMap(a.userId, props.memberMap)]
  if (isCurrentUser(a)) parts.push('you')
  if (a.pinned) parts.push('pinned')
  if (a.note) parts.push(`note: ${a.note}`)
  return parts.join(', ')
}

function handleAddClick(event: MouseEvent) {
  emit('assign', event.currentTarget as HTMLElement)
}
</script>

<template>
  <div class="flex min-h-[2rem] flex-col items-center gap-0.5">
    <button
      v-for="a in assignments"
      :key="a.id"
      type="button"
      class="group/cell focus-visible:outline-focus hover:ring-line relative inline-flex min-h-[44px] cursor-pointer items-center justify-center gap-1 rounded px-1.5 py-1 text-xs transition-shadow hover:ring-1 focus-visible:outline-2 focus-visible:outline-offset-2 sm:min-h-0"
      :class="
        isCurrentUser(a)
          ? 'bg-amber-300 text-amber-900 dark:bg-amber-400/20 dark:text-amber-100'
          : 'bg-btn-secondary-fill text-btn-secondary-ink'
      "
      :title="
        a.note
          ? `${getMemberNameFromMap(a.userId, memberMap)}: ${a.note}`
          : getMemberNameFromMap(a.userId, memberMap)
      "
      :aria-label="chipLabel(a)"
      @click="emit('editAssignment', a, $event.currentTarget as HTMLElement)"
    >
      <PushPinIcon
        v-if="a.pinned"
        class="size-3 shrink-0 text-amber-600 dark:text-amber-400"
      />
      <span class="truncate">{{
        getMemberNameFromMap(a.userId, memberMap)
      }}</span>
      <ChatBubbleLeftIcon
        v-if="a.note"
        aria-hidden="true"
        class="size-3 shrink-0 text-amber-600 dark:text-amber-400"
      />
    </button>
    <button
      v-if="hasEmptySlots"
      type="button"
      class="text-ink-muted focus-visible:outline-focus hover:bg-surface-sunken hover:text-ink inline-flex size-11 items-center justify-center rounded transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 sm:size-5"
      title="Assign member"
      aria-label="Assign member"
      @click="handleAddClick"
    >
      <PlusIcon class="size-3.5" />
    </button>
  </div>
</template>
