<script setup lang="ts">
import { ref, computed } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import VoteSummaryBar from '@/components/votes/VoteSummaryBar.vue'
import type { HydratedDateRange } from '@/composables/useHydratedEvent'
import { useCalendar } from '@/composables/useCalendar'

const props = defineProps<{
  open: boolean
  dateRanges: HydratedDateRange[]
  loading?: boolean
}>()

const emit = defineEmits<{
  close: []
  confirm: [dateRangeId: string]
}>()

const { formatDateDisplay } = useCalendar()

const selectedId = ref<string | null>(null)

// Top 3 ranked date ranges
const topRanges = computed(() => {
  return [...props.dateRanges]
    .sort((a, b) => {
      if (b.voteSummary.yes !== a.voteSummary.yes) {
        return b.voteSummary.yes - a.voteSummary.yes
      }
      if (b.voteSummary.preferably_not !== a.voteSummary.preferably_not) {
        return b.voteSummary.preferably_not - a.voteSummary.preferably_not
      }
      return b.voteSummary.no - a.voteSummary.no
    })
    .slice(0, 3)
})

function handleConfirm(): void {
  if (!selectedId.value) return
  emit('confirm', selectedId.value)
}

function handleClose(): void {
  selectedId.value = null
  emit('close')
}
</script>

<template>
  <BaseModal
    :open="open"
    title="Select Winning Date"
    size="lg"
    @close="handleClose"
  >
    <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
      Choose the winning date from the top-ranked options.
    </p>

    <div class="space-y-3">
      <button
        v-for="dateRange in topRanges"
        :key="dateRange.id"
        type="button"
        class="w-full rounded-lg border-2 p-4 text-left transition-colors"
        :class="
          selectedId === dateRange.id
            ? 'border-rose-500 bg-rose-50 dark:bg-rose-900/20'
            : 'border-gray-200 hover:border-gray-300 dark:border-gray-700 dark:hover:border-gray-600'
        "
        @click="selectedId = dateRange.id"
      >
        <div class="mb-2 flex items-center justify-between">
          <span class="font-medium text-gray-900 dark:text-white">
            {{ formatDateDisplay(dateRange.startDate) }}
            <span v-if="dateRange.startDate !== dateRange.endDate">
              - {{ formatDateDisplay(dateRange.endDate) }}
            </span>
          </span>
          <span class="text-sm text-gray-500 dark:text-gray-400">
            {{ dateRange.voteSummary.total }}
            {{ dateRange.voteSummary.total === 1 ? 'vote' : 'votes' }}
          </span>
        </div>
        <VoteSummaryBar :summary="dateRange.voteSummary" />
      </button>
    </div>

    <div class="mt-6 flex items-center justify-end gap-x-6">
      <button
        type="button"
        class="text-sm/6 font-semibold text-gray-900 dark:text-white"
        @click="handleClose"
      >
        Cancel
      </button>
      <button
        type="button"
        class="rounded-md bg-rose-500 px-3 py-2 text-sm font-semibold text-white hover:bg-rose-400 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="!selectedId || loading"
        @click="handleConfirm"
      >
        {{ loading ? 'Selecting...' : 'Confirm Winner' }}
      </button>
    </div>
  </BaseModal>
</template>
