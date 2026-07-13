<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import ChoreRosterSection from '@/components/chores/ChoreRosterSection.vue'

const route = useRoute()

const eventId = computed(() => route.params.id as string)
</script>

<template>
  <ChoreRosterSection :event-id="eventId" title="Chores" />
</template>
