<script setup lang="ts">
import { ref, computed } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import VoteSummaryBar from '@/components/votes/VoteSummaryBar.vue'
import FormActions from '@/components/form/FormActions.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import type { HydratedDateRange } from '@/composables/useHydratedEvent'
import { rankDateRanges } from '@/utils/poll'

const props = defineProps<{
  open: boolean
  dateRanges: HydratedDateRange[]
  loading?: boolean
}>()

const emit = defineEmits<{
  close: []
  confirm: [dateRangeId: string]
}>()

const selectedId = ref<string | null>(null)

// Top 3 ranked date ranges
const topRanges = computed(() => rankDateRanges(props.dateRanges).slice(0, 3))

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
    <form @submit.prevent="handleConfirm">
      <p class="text-ink-muted mb-4 text-sm">
        Choose the winning date from the top-ranked options.
      </p>

      <div class="space-y-3">
        <button
          v-for="dateRange in topRanges"
          :key="dateRange.id"
          type="button"
          data-testid="date-range-option"
          class="focus-visible:outline-focus w-full cursor-pointer rounded-lg border-2 p-4 text-left transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
          :class="
            selectedId === dateRange.id
              ? 'border-rose-500 bg-rose-50 dark:bg-rose-900/20'
              : 'border-line hover:border-line'
          "
          @click="selectedId = dateRange.id"
        >
          <div class="mb-2 flex items-center justify-between">
            <span class="text-ink font-medium">
              <DateRangeDisplay
                :start-date="dateRange.startDate"
                :end-date="dateRange.endDate"
              />
            </span>
            <span class="text-ink-muted text-sm">
              {{ dateRange.voteSummary.total }}
              {{ dateRange.voteSummary.total === 1 ? 'vote' : 'votes' }}
            </span>
          </div>
          <VoteSummaryBar :summary="dateRange.voteSummary" />
        </button>
      </div>

      <FormActions
        submit-label="Confirm Winner"
        loading-label="Selecting..."
        :loading="loading"
        :disabled="!selectedId"
        @cancel="handleClose"
      />
    </form>
  </BaseModal>
</template>
