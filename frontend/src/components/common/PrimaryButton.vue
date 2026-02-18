<script setup lang="ts">
defineProps<{
  disabled?: boolean
}>()

defineEmits<{
  click: []
}>()
</script>

<template>
  <button
    type="button"
    class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
    :disabled="disabled"
    @click="$emit('click')"
  >
    <slot />
  </button>
</template>
