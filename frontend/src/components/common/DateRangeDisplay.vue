<script setup lang="ts">
import { formatDateDisplay } from '@/utils/date'

defineProps<{
  startDate: string
  endDate: string
}>()
</script>

<template>
  <span>
    {{ formatDateDisplay(startDate) }}
    <template v-if="startDate !== endDate">
      &ndash; {{ formatDateDisplay(endDate) }}
    </template>
  </span>
</template>
