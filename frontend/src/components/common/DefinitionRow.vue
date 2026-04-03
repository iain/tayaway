<script setup lang="ts">
import { PencilIcon } from '@heroicons/vue/24/outline'
import IconButton from '@/components/common/IconButton.vue'

defineProps<{
  label: string
  editLabel?: string
  editTestid?: string
  valueClass?: string
}>()

defineEmits<{
  edit: []
}>()
</script>

<template>
  <div class="group flex items-center justify-between gap-2 py-3">
    <div class="min-w-0">
      <dt class="text-sm font-medium text-gray-500 dark:text-stone-400">
        {{ label }}
      </dt>
      <dd class="text-sm text-gray-900 dark:text-white" :class="valueClass">
        <slot />
      </dd>
    </div>
    <IconButton
      v-if="editLabel"
      hover-reveal
      :label="editLabel"
      :data-testid="editTestid"
      @click="$emit('edit')"
    >
      <PencilIcon class="size-4" />
    </IconButton>
  </div>
</template>
