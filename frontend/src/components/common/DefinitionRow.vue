<script setup lang="ts">
import { PencilIcon } from '@heroicons/vue/24/outline'

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
    <dt class="text-ink-muted text-sm font-medium">
      {{ label }}
    </dt>

    <!-- Edit mode -->
    <dd v-if="editing" class="mt-1">
      <slot name="editor" />
    </dd>

    <!-- View mode (editable: whole value row is the click target) -->
    <dd v-else-if="editLabel" class="mt-0.5">
      <button
        type="button"
        :aria-label="editLabel"
        :data-testid="editTestid"
        class="focus-visible:outline-focus hover:bg-surface-sunken focus-visible:bg-surface-sunken -mx-2 flex w-[calc(100%+1rem)] cursor-pointer items-center gap-1.5 rounded-md px-2 py-1 text-left transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
        @click="$emit('edit')"
      >
        <span class="text-ink min-w-0 flex-1 text-sm" :class="valueClass">
          <slot />
        </span>
        <PencilIcon
          class="text-ink-muted size-3.5 shrink-0"
          aria-hidden="true"
        />
      </button>
    </dd>

    <!-- View mode (read-only) -->
    <dd v-else class="mt-0.5">
      <span class="text-ink text-sm" :class="valueClass">
        <slot />
      </span>
    </dd>
  </div>
</template>
