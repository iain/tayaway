<script setup lang="ts">
import { ref, computed, watchEffect, nextTick } from 'vue'
import { PencilIcon, TrashIcon } from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import { VueDraggable } from 'vue-draggable-plus'
import type { SortableEvent } from 'vue-draggable-plus'
import {
  useTaskListsStore,
  useTaskItemsStore,
  useNotificationsStore,
} from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import TaskItemRow from './TaskItemRow.vue'
import type { PoolTaskList, PoolTaskItem } from '@/types/pool'

const props = defineProps<{
  taskList: PoolTaskList
  highlightedItemId?: string | null
}>()

const emit = defineEmits<{
  highlight: [itemId: string]
}>()

const taskListsStore = useTaskListsStore()
const taskItemsStore = useTaskItemsStore()
const pool = useObjectPoolStore()

const newItemContent = ref('')
const isAddingItem = ref(false)
const newItemInput = ref<HTMLInputElement | null>(null)
const isRenaming = ref(false)
const renameValue = ref('')

// IDs optimistically hidden after "clear completed" — survives pool re-imports
// caused by concurrent in-flight addItem/updateItem responses arriving as microtasks
// before Vue flushes the DOM.
const clearedIds = ref(new Set<string>())

// IDs the user has toggled to "complete" in this component instance.
// Persists across pool re-imports so handleClearCompleted can find the right IDs
// even if an in-flight addItem response clears the pending completedAt update.
const localCompletedIds = ref(new Set<string>())

// Local sorted list for drag-and-drop (synced from pool)
const itemsLocal = ref<PoolTaskItem[]>([])

watchEffect(() => {
  itemsLocal.value = pool
    .getAll('taskItem')
    .filter(
      (item) =>
        item.taskListId === props.taskList.id && !clearedIds.value.has(item.id)
    )
    .sort((a, b) => a.position - b.position)
})

const items = computed(() => itemsLocal.value)

const completedItems = computed(() =>
  items.value.filter((i) => i.completedAt !== null)
)
const hasCompleted = computed(() => completedItems.value.length > 0)

// Handles same-list reorders. @end fires on the SOURCE, so skip cross-list drags here.
async function handleItemDragEnd(event: SortableEvent) {
  if (event.from !== event.to) return

  const newIndex = event.newIndex
  if (newIndex === undefined) return

  const list = itemsLocal.value
  const movedItem = list[newIndex]
  if (!movedItem) return

  const before = newIndex > 0 ? (list[newIndex - 1]?.position ?? null) : null
  const after =
    newIndex < list.length - 1 ? (list[newIndex + 1]?.position ?? null) : null

  await taskItemsStore.repositionItem(
    movedItem.taskListId,
    movedItem.id,
    before,
    after
  )
}

// Handles cross-list drops INTO this list. @add fires on the TARGET with
// v-model already updated, so itemsLocal[newIndex] is the moved item
// (taskListId still points to source list until the optimistic update).
async function handleItemDragAdd(event: SortableEvent) {
  const newIndex = event.newIndex
  if (newIndex === undefined) return

  const list = itemsLocal.value
  const movedItem = list[newIndex]
  if (!movedItem) return

  const sourceListId = movedItem.taskListId
  const targetListId = props.taskList.id
  if (sourceListId === targetListId) return // shouldn't happen in @add

  const before = newIndex > 0 ? (list[newIndex - 1]?.position ?? null) : null
  const after =
    newIndex < list.length - 1 ? (list[newIndex + 1]?.position ?? null) : null

  await taskItemsStore.repositionItem(
    sourceListId,
    movedItem.id,
    before,
    after,
    targetListId
  )
}

async function handleAddItem(): Promise<void> {
  const content = newItemContent.value.trim()
  if (!content) return

  newItemContent.value = ''
  isAddingItem.value = true
  try {
    const { queued } = await taskItemsStore.addItem(props.taskList.id, content)
    if (queued) {
      useNotificationsStore().showInfo('Item will be added when back online')
    }
  } catch {
    // error shown via store
  } finally {
    isAddingItem.value = false
    await nextTick()
    newItemInput.value?.focus()
  }
}

async function handleToggle(item: PoolTaskItem): Promise<void> {
  const completing = !item.completedAt
  if (completing) {
    localCompletedIds.value.add(item.id)
  } else {
    localCompletedIds.value.delete(item.id)
  }
  try {
    await taskItemsStore.updateItem(props.taskList.id, item.id, {
      completed: completing,
    })
  } catch {
    // error shown via store — undo local tracking
    if (completing) {
      localCompletedIds.value.delete(item.id)
    } else {
      localCompletedIds.value.add(item.id)
    }
  }
}

async function handleDeleteItem(item: PoolTaskItem): Promise<void> {
  try {
    await taskItemsStore.deleteItem(props.taskList.id, item.id)
  } catch {
    // error shown via store
  }
}

async function handleClearCompleted(): Promise<void> {
  // Merge pool-derived completed IDs with locally-tracked ones. The local set
  // covers the race where an in-flight addItem response clears the pending
  // completedAt update before the click handler runs, leaving completedItems empty.
  const poolIds = completedItems.value.map((i) => i.id)
  const allIds = [...new Set([...poolIds, ...localCompletedIds.value])]
  localCompletedIds.value.clear()
  for (const id of allIds) {
    clearedIds.value.add(id)
  }
  try {
    await taskItemsStore.clearCompleted(props.taskList.id, allIds)
  } catch {
    // Restore visibility on error
    for (const id of allIds) {
      clearedIds.value.delete(id)
    }
  }
}

function startRename(): void {
  renameValue.value = props.taskList.name
  isRenaming.value = true
}

async function commitRename(): Promise<void> {
  const name = renameValue.value.trim()
  isRenaming.value = false
  if (!name || name === props.taskList.name) return

  try {
    await taskListsStore.updateTaskList(props.taskList.id, name)
  } catch {
    // error shown via store
  }
}

async function handleDeleteList(): Promise<void> {
  try {
    await taskListsStore.deleteTaskList(props.taskList.id)
  } catch {
    // error shown via store
  }
}

defineExpose({
  focusInput(): void {
    newItemInput.value?.focus()
  },
  toggleItem(item: PoolTaskItem): void {
    void handleToggle(item)
  },
  deleteItem(item: PoolTaskItem): void {
    void handleDeleteItem(item)
  },
})
</script>

<template>
  <div
    class="overflow-hidden rounded-lg bg-white shadow dark:bg-stone-800"
    data-testid="task-list-card"
  >
    <div class="px-4 py-4 sm:px-6">
      <!-- Header -->
      <div class="mb-3 flex items-center justify-between gap-2">
        <span
          class="list-drag-handle cursor-grab touch-none text-gray-300 hover:text-gray-400 dark:text-stone-600 dark:hover:text-stone-400"
          data-testid="task-list-drag-handle"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="size-5"
            fill="currentColor"
            viewBox="0 0 24 24"
          >
            <circle cx="9" cy="5" r="1.5" />
            <circle cx="15" cy="5" r="1.5" />
            <circle cx="9" cy="12" r="1.5" />
            <circle cx="15" cy="12" r="1.5" />
            <circle cx="9" cy="19" r="1.5" />
            <circle cx="15" cy="19" r="1.5" />
          </svg>
        </span>

        <div v-if="isRenaming" class="flex flex-1 items-center gap-2">
          <input
            v-model="renameValue"
            type="text"
            data-testid="rename-list-input"
            class="flex-1 rounded-md bg-gray-100 px-2 py-1 text-sm font-semibold text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10"
            @keyup.enter="commitRename"
            @keyup.escape="isRenaming = false"
            @blur="commitRename"
          />
        </div>
        <h2
          v-else
          class="flex-1 text-base font-semibold text-gray-900 dark:text-white"
        >
          {{ taskList.name }}
        </h2>

        <div class="flex shrink-0 items-center gap-1">
          <TextButton
            v-if="hasCompleted"
            variant="secondary"
            data-testid="clear-completed-button"
            class="text-xs"
            @click="handleClearCompleted"
          >
            Clear {{ completedItems.length }} completed
          </TextButton>
          <IconButton
            label="Rename list"
            data-testid="rename-list-button"
            @click="startRename"
          >
            <PencilIcon class="size-4" />
          </IconButton>
          <IconButton
            variant="danger"
            label="Delete list"
            data-testid="delete-list-button"
            @click="handleDeleteList"
          >
            <TrashIcon class="size-4" />
          </IconButton>
        </div>
      </div>

      <!-- Items (always rendered so empty lists can receive cross-list drops) -->
      <VueDraggable
        v-model="itemsLocal"
        tag="ul"
        data-testid="task-items-list"
        class="divide-y divide-gray-100 dark:divide-stone-700"
        :class="{ 'min-h-8': items.length === 0 }"
        group="task-items"
        handle=".item-drag-handle"
        :animation="150"
        ghost-class="opacity-50"
        @end="handleItemDragEnd"
        @add="handleItemDragAdd"
      >
        <TaskItemRow
          v-for="item in items"
          :key="item.id"
          :item="item"
          :highlighted="item.id === highlightedItemId"
          @toggle="handleToggle"
          @delete="handleDeleteItem"
          @highlight="emit('highlight', $event.id)"
        />
      </VueDraggable>

      <!-- Add item input -->
      <div class="mt-3 flex items-center gap-2">
        <input
          ref="newItemInput"
          v-model="newItemContent"
          type="text"
          placeholder="Add an item..."
          class="flex-1 rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
          :disabled="isAddingItem"
          @keyup.enter="handleAddItem"
          @keyup.escape="newItemInput?.blur()"
        />
        <AppButton
          size="sm"
          :disabled="!newItemContent.trim() || isAddingItem"
          @click="handleAddItem"
        >
          Add
        </AppButton>
      </div>
    </div>
  </div>
</template>
