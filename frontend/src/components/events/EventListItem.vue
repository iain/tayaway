<script setup lang="ts">
import { ChevronRightIcon } from '@heroicons/vue/24/outline'
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
      <div class="flex items-center justify-between gap-3">
        <div class="min-w-0 flex-1">
          <h3
            data-testid="event-name"
            class="text-ink truncate text-lg font-semibold"
          >
            {{ event.name }}
          </h3>
          <p
            v-if="event.description"
            class="text-ink-muted mt-1 line-clamp-2 text-sm"
            :title="event.description"
          >
            {{ event.description }}
          </p>
          <div class="text-ink-muted mt-2 flex items-center gap-3 text-sm">
            <slot name="meta" />
            <span class="text-ink-muted">by {{ ownerName }}</span>
          </div>
        </div>
        <ChevronRightIcon
          class="text-ink-muted size-5 shrink-0"
          aria-hidden="true"
        />
      </div>
    </div>
  </BaseCard>
</template>
