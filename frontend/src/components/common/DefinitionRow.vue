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
    <dt class="text-sm font-medium text-ink-muted">
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
        class="-mx-2 flex w-[calc(100%+1rem)] cursor-pointer items-center gap-1.5 rounded-md px-2 py-1 text-left transition-colors hover:bg-gray-100 focus-visible:bg-gray-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus dark:hover:bg-white/[0.04] dark:focus-visible:bg-white/[0.04]"
        @click="$emit('edit')"
      >
        <span
          class="min-w-0 flex-1 text-sm text-ink"
          :class="valueClass"
        >
          <slot />
        </span>
        <PencilIcon
          class="size-3.5 shrink-0 text-ink-muted"
          aria-hidden="true"
        />
      </button>
    </dd>

    <!-- View mode (read-only) -->
    <dd v-else class="mt-0.5">
      <span class="text-sm text-ink" :class="valueClass">
        <slot />
      </span>
    </dd>
  </div>
</template>
