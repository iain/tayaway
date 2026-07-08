<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  ChevronDownIcon,
  ChevronUpIcon,
  ClockIcon,
  TrashIcon,
} from '@heroicons/vue/24/outline'
import BaseModal from '@/components/common/BaseModal.vue'
import IconButton from '@/components/common/IconButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import AppButton from '@/components/common/AppButton.vue'
import { useChoreRostersStore } from '@/stores/choreRosters'
import { positionForReorder } from '@/utils/position'
import type { PoolChore } from '@/types/pool'

// The mobile home for chore-level settings that live in the desktop grid's
// column headers: order, reminder time, and deletion. The day list can't carry
// them because a chore repeats under every day, so they collect here instead.
const props = defineProps<{
  open: boolean
  chores: PoolChore[]
  rosterId: string
}>()

const emit = defineEmits<{
  close: []
}>()

const store = useChoreRostersStore()

const sortedChores = computed(() =>
  [...props.chores].sort((a, b) => a.position - b.position)
)

const confirmingId = ref<string | null>(null)

function move(chore: PoolChore, direction: 'up' | 'down'): void {
  const list = sortedChores.value
  const i = list.findIndex((c) => c.id === chore.id)
  const target = direction === 'up' ? i - 1 : i + 1
  if (target < 0 || target >= list.length) return

  store.updateChore(props.rosterId, chore.id, {
    position: positionForReorder(
      list.map((c) => c.position),
      i,
      direction
    ),
  })
}

function onTimeChange(chore: PoolChore, event: Event): void {
  const next = (event.target as HTMLInputElement).value || null
  if (next !== (chore.time ?? null)) {
    store.updateChore(props.rosterId, chore.id, { time: next })
  }
}

async function confirmDelete(chore: PoolChore): Promise<void> {
  await store.deleteChore(props.rosterId, chore.id)
  confirmingId.value = null
}
</script>

<template>
  <BaseModal
    :open="open"
    title="Manage chores"
    size="md"
    @close="emit('close')"
  >
    <p v-if="sortedChores.length === 0" class="text-ink-muted text-sm">
      Add a chore first, then come back here to set times and order.
    </p>

    <ul v-else class="divide-line-faint divide-y">
      <li
        v-for="(chore, index) in sortedChores"
        :key="chore.id"
        :data-chore-id="chore.id"
        class="py-3 first:pt-0 last:pb-1"
      >
        <div class="flex items-center gap-3">
          <div class="flex shrink-0 flex-col">
            <IconButton
              :label="`Move ${chore.name} earlier`"
              :data-testid="`move-up-${chore.id}`"
              :disabled="index === 0"
              @click="move(chore, 'up')"
            >
              <ChevronUpIcon class="size-5" />
            </IconButton>
            <IconButton
              :label="`Move ${chore.name} later`"
              :data-testid="`move-down-${chore.id}`"
              :disabled="index === sortedChores.length - 1"
              @click="move(chore, 'down')"
            >
              <ChevronDownIcon class="size-5" />
            </IconButton>
          </div>

          <div class="min-w-0 flex-1">
            <p class="text-ink truncate font-medium">{{ chore.name }}</p>
            <div class="text-ink-muted mt-1 flex items-center gap-1.5">
              <ClockIcon class="size-4 shrink-0" aria-hidden="true" />
              <input
                :value="chore.time ?? ''"
                type="time"
                :aria-label="`Reminder time for ${chore.name}`"
                class="bg-surface-sunken text-ink outline-line focus:outline-focus rounded-md px-2 py-1 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 sm:text-sm"
                @change="onTimeChange(chore, $event)"
              />
            </div>
          </div>

          <IconButton
            variant="danger"
            :label="`Delete ${chore.name}`"
            :data-testid="`delete-${chore.id}`"
            class="shrink-0"
            @click="confirmingId = chore.id"
          >
            <TrashIcon class="size-5" />
          </IconButton>
        </div>

        <div
          v-if="confirmingId === chore.id"
          class="bg-surface-urgent ring-ring-urgent mt-3 rounded-md p-3 ring-1"
        >
          <p class="text-ink text-sm">
            Delete "{{ chore.name }}" and all of its assignments?
          </p>
          <div class="mt-3 flex justify-end gap-3">
            <TextButton
              variant="secondary"
              :data-testid="`cancel-delete-${chore.id}`"
              @click="confirmingId = null"
            >
              Cancel
            </TextButton>
            <AppButton
              variant="danger"
              size="sm"
              :data-testid="`confirm-delete-${chore.id}`"
              @click="confirmDelete(chore)"
            >
              Delete
            </AppButton>
          </div>
        </div>
      </li>
    </ul>
  </BaseModal>
</template>
