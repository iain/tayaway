<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useChoreRostersStore } from '@/stores/choreRosters'
import PushPinIcon from '@/components/icons/PushPinIcon.vue'
import type { PoolChoreAssignment, PoolMember } from '@/types/pool'
import { getMemberNameFromMap } from '@/utils/member'
import TextButton from '@/components/common/TextButton.vue'
import AppButton from '@/components/common/AppButton.vue'

const props = defineProps<{
  assignment: PoolChoreAssignment
  anchorEl: HTMLElement
  rosterId: string
  memberMap: Map<string, PoolMember>
}>()

const emit = defineEmits<{
  close: []
}>()

const choreRostersStore = useChoreRostersStore()
const note = ref(props.assignment.note ?? '')
const popoverRef = ref<HTMLDivElement | null>(null)

async function handleSaveNote() {
  const trimmed = note.value.trim()
  if (trimmed === (props.assignment.note ?? '')) {
    emit('close')
    return
  }
  await choreRostersStore.updateAssignment(
    props.rosterId,
    props.assignment.id,
    {
      note: trimmed || undefined,
    }
  )
  emit('close')
}

async function handleTogglePin() {
  await choreRostersStore.updateAssignment(
    props.rosterId,
    props.assignment.id,
    { pinned: !props.assignment.pinned }
  )
  emit('close')
}

async function handleRemove() {
  await choreRostersStore.deleteAssignment(props.rosterId, props.assignment.id)
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
    <div class="mb-2 flex items-center justify-between">
      <p class="text-ink-muted text-xs font-medium">
        {{ getMemberNameFromMap(assignment.userId, memberMap) }}
      </p>
      <button
        type="button"
        class="focus-visible:outline-focus cursor-pointer rounded p-1 transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
        :class="
          assignment.pinned
            ? 'text-state-warning-ink hover:bg-state-warning-fill'
            : 'text-ink-muted hover:bg-surface-sunken hover:text-ink'
        "
        :title="assignment.pinned ? 'Unpin' : 'Pin'"
        @click="handleTogglePin"
      >
        <PushPinIcon class="size-3.5" />
      </button>
    </div>

    <input
      v-model="note"
      type="text"
      placeholder="Note (optional)"
      class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder focus:outline-focus mb-3 block w-full rounded-md px-2 py-1 text-sm outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2"
      @keydown.enter="handleSaveNote"
    />

    <div class="flex items-center justify-between">
      <TextButton variant="danger" @click="handleRemove"> Remove </TextButton>
      <AppButton size="sm" @click="handleSaveNote"> Save </AppButton>
    </div>
  </div>
</template>
