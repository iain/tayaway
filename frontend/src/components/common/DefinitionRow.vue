<script setup lang="ts">
import { PencilIcon } from '@heroicons/vue/24/outline'
import IconButton from '@/components/common/IconButton.vue'

defineProps<{
  label: string
  editLabel?: string
  editTestid?: string
  valueClass?: string
  editing?: boolean
}>()

defineEmits<{
  edit: []
}>()
</script>

<template>
  <div class="py-3">
    <dt class="text-sm font-medium text-gray-500 dark:text-stone-400">
      {{ label }}
    </dt>

    <!-- Edit mode -->
    <dd v-if="editing" class="mt-1">
      <slot name="editor" />
    </dd>

    <!-- View mode -->
    <dd v-else class="group mt-0.5 flex items-center gap-1.5">
      <span
        class="min-w-0 text-sm text-gray-900 dark:text-white"
        :class="valueClass"
      >
        <slot />
      </span>
      <IconButton
        v-if="editLabel"
        hover-reveal
        :label="editLabel"
        :data-testid="editTestid"
        class="shrink-0"
        @click="$emit('edit')"
      >
        <PencilIcon class="size-3.5" />
      </IconButton>
    </dd>
  </div>
</template>
