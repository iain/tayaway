<script setup lang="ts">
import { watchEffect } from 'vue'
import { useRouter } from 'vue-router'
import { ClipboardDocumentListIcon } from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import { useFocusedEvent } from '@/composables/useFocusedEvent'

// Chores live on the focused event's own tab. This URL survives for bookmarks
// and older clients, so it hands off there rather than keeping a second copy
// of the roster around. `watchEffect` rather than a router guard: on a cold
// start the pool is still hydrating and there's no focused event to redirect
// to yet, and this picks it up the moment one arrives.
const router = useRouter()
const { focusedEvent } = useFocusedEvent()

watchEffect(() => {
  const event = focusedEvent.value
  if (event) router.replace(`/events/${event.id}/chores`)
})
</script>

<template>
  <EmptyState
    v-if="!focusedEvent"
    :icon="ClipboardDocumentListIcon"
    :heading-level="2"
    heading="No active event"
    description="Chores show up here once an event is under way or coming up."
  >
    <AppButton to="/events">View events</AppButton>
  </EmptyState>
</template>
