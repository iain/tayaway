<script setup lang="ts">
interface Props {
  count: number
}
const props = defineProps<Props>()
</script>

<template>
  <span
    v-if="props.count > 0"
    :aria-label="`${props.count} unread`"
    class="ml-2 inline-flex h-2 w-2 rounded-full bg-brand"
  />
</template>
