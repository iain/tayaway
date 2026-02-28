<script setup lang="ts">
import { computed } from 'vue'
import {
  PlusIcon,
  MapPinIcon,
  ChatBubbleLeftIcon,
} from '@heroicons/vue/24/outline'
import type { PoolChoreAssignment, PoolMember } from '@/types/pool'

const props = defineProps<{
  assignments: PoolChoreAssignment[]
  peoplePerDay: number
  memberMap: Map<string, PoolMember>
}>()

const emit = defineEmits<{
  assign: [anchorEl: HTMLElement]
  editAssignment: [assignment: PoolChoreAssignment, anchorEl: HTMLElement]
}>()

const hasEmptySlots = computed(
  () => props.assignments.length < props.peoplePerDay
)

function getMemberName(userId: string): string {
  const member = props.memberMap.get(userId)
  if (!member) return '?'
  return member.name ?? member.email.split('@')[0] ?? member.email
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
      class="group/cell relative inline-flex cursor-pointer items-center gap-0.5 rounded px-1.5 py-0.5 text-xs transition-shadow hover:ring-1 hover:ring-gray-300 dark:hover:ring-stone-500"
      :class="
        a.pinned
          ? 'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300'
          : 'bg-gray-100 text-gray-700 dark:bg-stone-700 dark:text-stone-300'
      "
      :title="
        a.note
          ? `${getMemberName(a.userId)}: ${a.note}`
          : getMemberName(a.userId)
      "
      @click="emit('editAssignment', a, $event.currentTarget as HTMLElement)"
    >
      <MapPinIcon v-if="a.pinned" class="size-3 shrink-0" />
      <span class="truncate">{{ getMemberName(a.userId) }}</span>
      <ChatBubbleLeftIcon
        v-if="a.note"
        class="size-3 shrink-0 text-gray-400 dark:text-stone-500"
      />
    </button>
    <button
      v-if="hasEmptySlots"
      type="button"
      class="inline-flex size-5 items-center justify-center rounded text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600 dark:text-stone-500 dark:hover:bg-stone-700 dark:hover:text-stone-300"
      title="Assign member"
      @click="handleAddClick"
    >
      <PlusIcon class="size-3.5" />
    </button>
  </div>
</template>
