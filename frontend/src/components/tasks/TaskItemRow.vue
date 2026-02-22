<script setup lang="ts">
import { TrashIcon } from '@heroicons/vue/24/outline'
import type { PoolTaskItem } from '@/types/pool'

defineProps<{
  item: PoolTaskItem
}>()

const emit = defineEmits<{
  toggle: [item: PoolTaskItem]
  delete: [item: PoolTaskItem]
}>()
</script>

<template>
  <li class="flex items-center gap-3 py-2" data-testid="task-item-row">
    <span
      class="item-drag-handle cursor-grab touch-none text-gray-300 hover:text-gray-400 dark:text-stone-600 dark:hover:text-stone-400"
      data-testid="task-item-drag-handle"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="size-4"
        fill="currentColor"
        viewBox="0 0 24 24"
      >
        <circle cx="9" cy="5" r="1.5" />
        <circle cx="15" cy="5" r="1.5" />
        <circle cx="9" cy="12" r="1.5" />
        <circle cx="15" cy="12" r="1.5" />
        <circle cx="9" cy="19" r="1.5" />
        <circle cx="15" cy="19" r="1.5" />
      </svg>
    </span>
    <input
      type="checkbox"
      :checked="!!item.completedAt"
      class="size-4 cursor-pointer accent-rose-500"
      @change="emit('toggle', item)"
    />
    <span
      class="flex-1 cursor-pointer text-sm"
      :class="
        item.completedAt
          ? 'text-gray-400 line-through dark:text-stone-500'
          : 'text-gray-900 dark:text-white'
      "
      @click="emit('toggle', item)"
    >
      {{ item.content }}
    </span>
    <button
      type="button"
      class="text-gray-400 hover:text-red-500 dark:text-stone-500 dark:hover:text-red-400"
      @click="emit('delete', item)"
    >
      <span class="sr-only">Delete</span>
      <TrashIcon class="size-4" />
    </button>
  </li>
</template>
