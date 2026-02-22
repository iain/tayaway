<script setup lang="ts">
import { computed, watchEffect } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { isPollResolved } from '@/utils/poll'
import { eventIsPast } from '@/utils/event'

const route = useRoute()
const router = useRouter()
const eventId = computed(() => route.params.id as string)
const { event } = useHydratedEvent(eventId)

watchEffect(() => {
  if (!event.value) return
  const poll = event.value.datePoll
  if (!isPollResolved(poll)) {
    router.replace(`/events/${eventId.value}/planning`)
  } else if (eventIsPast(event.value)) {
    router.replace(`/events/${eventId.value}/expenses`)
  } else {
    router.replace(`/events/${eventId.value}/rsvp`)
  }
})
</script>

<!-- eslint-disable vue/valid-template-root -->
<template></template>
