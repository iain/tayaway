<script setup lang="ts">
import { TrashIcon } from '@heroicons/vue/24/outline'
import IconButton from '@/components/common/IconButton.vue'
import type { PoolTaskItem } from '@/types/pool'

defineProps<{
  item: PoolTaskItem
  highlighted?: boolean
}>()

const emit = defineEmits<{
  toggle: [item: PoolTaskItem]
  delete: [item: PoolTaskItem]
  highlight: [item: PoolTaskItem]
}>()
</script>

<template>
  <li
    class="-mx-2 flex items-center gap-3 rounded px-2 py-3"
    :class="highlighted ? 'bg-amber-50 dark:bg-amber-900/15' : ''"
    :data-item-id="item.id"
    :data-highlighted="highlighted ? 'true' : undefined"
    data-testid="task-item-row"
    @mouseenter="emit('highlight', item)"
  >
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
    <label class="flex flex-1 cursor-pointer items-center gap-3">
      <input
        type="checkbox"
        :checked="!!item.completedAt"
        class="size-5 cursor-pointer accent-rose-500"
        @change="emit('toggle', item)"
      />
      <span
        class="flex-1 text-base"
        :class="
          item.completedAt
            ? 'text-gray-400 line-through dark:text-stone-500'
            : 'text-gray-900 dark:text-white'
        "
        :data-completed="item.completedAt ? 'true' : undefined"
      >
        {{ item.content }}
      </span>
    </label>
    <IconButton variant="danger" label="Delete" @click="emit('delete', item)">
      <TrashIcon class="size-4" />
    </IconButton>
  </li>
</template>
