<script setup lang="ts">
import { ClipboardDocumentListIcon } from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import ChoreRosterSection from '@/components/chores/ChoreRosterSection.vue'
import { useActiveChoreEvents } from '@/composables/useActiveChoreEvents'
import { formatDateRange } from '@/utils/date'

const { activeEvents } = useActiveChoreEvents()

// The event's name heads each section, so two overlapping trips are never
// mistaken for one another; the dates say which days the grid covers.
function dateRange(event: {
  startDate: string | null
  endDate: string | null
}) {
  if (!event.startDate || !event.endDate) return undefined
  return formatDateRange(event.startDate, event.endDate)
}
</script>

<template>
  <div>
    <PageHeader title="Chores" :icon="ClipboardDocumentListIcon" />

    <div v-if="activeEvents.length > 0" class="flex flex-col gap-10">
      <ChoreRosterSection
        v-for="event in activeEvents"
        :key="event.id"
        :event-id="event.id"
        :title="event.name"
        :subtitle="dateRange(event)"
        heading-style="section"
        :scroll-to-today="activeEvents.length === 1"
      />
    </div>

    <EmptyState
      v-else
      :icon="ClipboardDocumentListIcon"
      :heading-level="2"
      heading="No active event"
      description="Chores show up here once an event is under way or coming up."
    >
      <AppButton to="/events">View events</AppButton>
    </EmptyState>
  </div>
</template>
