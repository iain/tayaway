<script setup lang="ts">
import { useCalendar } from '@/composables/useCalendar'

defineProps<{
  startDate: string
  endDate: string
}>()

const { formatDateDisplay } = useCalendar()
</script>

<template>
  <span>
    {{ formatDateDisplay(startDate) }}
    <template v-if="startDate !== endDate">
      &ndash; {{ formatDateDisplay(endDate) }}
    </template>
  </span>
</template>
