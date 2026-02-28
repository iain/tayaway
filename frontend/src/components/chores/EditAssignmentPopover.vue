<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useChoreRostersStore } from '@/stores/choreRosters'
import PushPinIcon from '@/components/icons/PushPinIcon.vue'
import type { PoolChoreAssignment, PoolMember } from '@/types/pool'

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

function getMemberName(userId: string): string {
  const member = props.memberMap.get(userId)
  if (!member) return '?'
  return member.name ?? member.email.split('@')[0] ?? member.email
}

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
    class="fixed z-50 w-64 rounded-lg border border-gray-200 bg-white p-3 shadow-lg dark:border-stone-700 dark:bg-stone-800"
    :style="{
      top: `${anchorEl.getBoundingClientRect().bottom + 4}px`,
      left: `${anchorEl.getBoundingClientRect().left}px`,
    }"
  >
    <div class="mb-2 flex items-center justify-between">
      <p class="text-xs font-medium text-gray-500 dark:text-stone-400">
        {{ getMemberName(assignment.userId) }}
      </p>
      <button
        type="button"
        class="cursor-pointer rounded p-1 transition-colors"
        :class="
          assignment.pinned
            ? 'text-amber-600 hover:bg-amber-50 hover:text-amber-700 dark:text-amber-400 dark:hover:bg-amber-900/30 dark:hover:text-amber-300'
            : 'text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:text-stone-500 dark:hover:bg-stone-700 dark:hover:text-stone-300'
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
      class="mb-3 block w-full rounded-md bg-gray-100 px-2 py-1 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
      @keydown.enter="handleSaveNote"
    />

    <div class="flex items-center justify-between">
      <button
        type="button"
        class="cursor-pointer text-xs text-red-600 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300"
        @click="handleRemove"
      >
        Remove
      </button>
      <button
        type="button"
        class="cursor-pointer rounded-md bg-rose-600 px-2 py-1 text-xs font-medium text-white hover:bg-rose-500"
        @click="handleSaveNote"
      >
        Save
      </button>
    </div>
  </div>
</template>
