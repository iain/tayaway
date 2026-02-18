<script setup lang="ts">
import { PencilIcon, TrashIcon } from '@heroicons/vue/24/outline'
import type { ObjectTypeMap } from '@/types/pool'

defineProps<{
  event: ObjectTypeMap['event']
  ownerName: string
  isOwner: boolean
}>()

defineEmits<{
  click: []
  edit: []
  delete: []
}>()
</script>

<template>
  <li
    :data-testid="`event-item-${event.id}`"
    class="cursor-pointer overflow-hidden rounded-lg bg-white shadow transition-all hover:ring-2 hover:ring-rose-500 dark:bg-stone-800"
    @click="$emit('click')"
  >
    <div class="px-4 py-5 sm:px-6">
      <div class="flex items-center justify-between">
        <div class="min-w-0 flex-1">
          <h3
            data-testid="event-name"
            class="truncate text-lg font-semibold text-gray-900 dark:text-white"
          >
            {{ event.name }}
          </h3>
          <p
            v-if="event.description"
            class="mt-1 text-sm text-gray-500 dark:text-stone-400"
          >
            {{ event.description }}
          </p>
          <div
            class="mt-2 flex items-center gap-3 text-sm text-gray-600 dark:text-stone-300"
          >
            <slot name="meta" />
            <span class="text-gray-400 dark:text-stone-500"
              >by {{ ownerName }}</span
            >
          </div>
        </div>
        <div v-if="isOwner" class="ml-4 flex items-center gap-2">
          <button
            type="button"
            class="p-2 text-gray-400 hover:text-cyan-600 dark:hover:text-cyan-400"
            @click.stop="$emit('edit')"
          >
            <PencilIcon class="size-5" />
            <span class="sr-only">Edit</span>
          </button>
          <button
            type="button"
            class="p-2 text-gray-400 hover:text-red-600 dark:hover:text-red-400"
            @click.stop="$emit('delete')"
          >
            <TrashIcon class="size-5" />
            <span class="sr-only">Delete</span>
          </button>
        </div>
      </div>
    </div>
  </li>
</template>
