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
  <li class="flex items-center gap-3 py-2">
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
