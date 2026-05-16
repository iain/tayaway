<script setup lang="ts">
interface Props {
  count: number
}
const props = defineProps<Props>()
</script>

<template>
  <span v-if="props.count > 0" class="ml-2 inline-flex items-center">
    <span aria-hidden="true" class="inline-flex h-2 w-2 rounded-full bg-brand" />
    <span class="sr-only">{{ props.count }} unread</span>
  </span>
</template>
