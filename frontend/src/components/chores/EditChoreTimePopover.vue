<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useChoreRostersStore } from '@/stores/choreRosters'
import type { PoolChore } from '@/types/pool'
import TextButton from '@/components/common/TextButton.vue'
import AppButton from '@/components/common/AppButton.vue'

const props = defineProps<{
  chore: PoolChore
  anchorEl: HTMLElement
  rosterId: string
}>()

const emit = defineEmits<{
  close: []
}>()

const choreRostersStore = useChoreRostersStore()
const time = ref(props.chore.time ?? '')
const popoverRef = ref<HTMLDivElement | null>(null)

async function handleSave() {
  const next = time.value || null
  if (next === (props.chore.time ?? null)) {
    emit('close')
    return
  }
  await choreRostersStore.updateChore(props.rosterId, props.chore.id, {
    time: next,
  })
  emit('close')
}

async function handleClear() {
  await choreRostersStore.updateChore(props.rosterId, props.chore.id, {
    time: null,
  })
  emit('close')
}

function handleClickOutside(event: MouseEvent) {
  if (popoverRef.value && !popoverRef.value.contains(event.target as Node)) {
    emit('close')
  }
}

onMounted(() => {
  document.addEventListener('mousedown', handleClickOutside)
})

onBeforeUnmount(() => {
  document.removeEventListener('mousedown', handleClickOutside)
})
</script>

<template>
  <div
    ref="popoverRef"
    class="border-line bg-surface fixed z-50 w-64 rounded-lg border p-3 shadow-lg"
    :style="{
      top: `${anchorEl.getBoundingClientRect().bottom + 4}px`,
      left: `${anchorEl.getBoundingClientRect().left}px`,
    }"
  >
    <label
      :for="`chore-time-${chore.id}`"
      class="text-ink-muted mb-2 block text-xs font-medium"
    >
      Reminder time for {{ chore.name }}
    </label>

    <input
      :id="`chore-time-${chore.id}`"
      v-model="time"
      type="time"
      class="bg-surface-sunken text-ink outline-line focus:outline-focus mb-3 block w-full rounded-md px-2 py-1 text-sm outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2"
      @keydown.enter="handleSave"
    />

    <div class="flex items-center justify-between">
      <TextButton v-if="chore.time" variant="danger" @click="handleClear">
        Clear
      </TextButton>
      <span v-else />
      <AppButton size="sm" @click="handleSave"> Save </AppButton>
    </div>
  </div>
</template>
