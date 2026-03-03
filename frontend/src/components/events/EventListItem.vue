<script setup lang="ts">
import type { ObjectTypeMap } from '@/types/pool'
import BaseCard from '@/components/common/BaseCard.vue'

defineProps<{
  event: ObjectTypeMap['event']
  ownerName: string
}>()

defineEmits<{
  click: []
}>()
</script>

<template>
  <BaseCard
    as="li"
    interactive
    class="overflow-hidden"
    :data-testid="`event-item-${event.id}`"
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
      </div>
    </div>
  </BaseCard>
</template>
