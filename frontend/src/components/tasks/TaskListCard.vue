<script setup lang="ts">
import { ref, computed } from 'vue'
import { PencilIcon, TrashIcon } from '@heroicons/vue/24/outline'
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
}>()

const taskListsStore = useTaskListsStore()
const taskItemsStore = useTaskItemsStore()
const pool = useObjectPoolStore()

const newItemContent = ref('')
const isAddingItem = ref(false)
const isRenaming = ref(false)
const renameValue = ref('')

const items = computed((): PoolTaskItem[] =>
  pool
    .getMany('taskItem', props.taskList.itemIds)
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
)

const completedItems = computed(() =>
  items.value.filter((i) => i.completedAt !== null)
)
const hasCompleted = computed(() => completedItems.value.length > 0)

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
  }
}

async function handleToggle(item: PoolTaskItem): Promise<void> {
  try {
    await taskItemsStore.updateItem(props.taskList.id, item.id, {
      completed: !item.completedAt,
    })
  } catch {
    // error shown via store
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
  const ids = completedItems.value.map((i) => i.id)
  try {
    await taskItemsStore.clearCompleted(props.taskList.id, ids)
  } catch {
    // error shown via store
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
</script>

<template>
  <div
    class="overflow-hidden rounded-lg bg-white shadow dark:bg-stone-800"
    data-testid="task-list-card"
  >
    <div class="px-4 py-4 sm:px-6">
      <!-- Header -->
      <div class="mb-3 flex items-center justify-between gap-2">
        <div v-if="isRenaming" class="flex flex-1 items-center gap-2">
          <input
            v-model="renameValue"
            type="text"
            class="flex-1 rounded-md bg-gray-100 px-2 py-1 text-sm font-semibold text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-amber-500 dark:bg-white/5 dark:text-white dark:outline-white/10"
            @keyup.enter="commitRename"
            @keyup.escape="isRenaming = false"
            @blur="commitRename"
          />
        </div>
        <h2
          v-else
          class="text-base font-semibold text-gray-900 dark:text-white"
        >
          {{ taskList.name }}
        </h2>

        <div class="flex shrink-0 items-center gap-1">
          <button
            type="button"
            class="rounded p-1 text-gray-400 hover:text-gray-600 dark:text-stone-500 dark:hover:text-stone-300"
            title="Rename list"
            @click="startRename"
          >
            <PencilIcon class="size-4" />
          </button>
          <button
            type="button"
            class="rounded p-1 text-gray-400 hover:text-red-500 dark:text-stone-500 dark:hover:text-red-400"
            title="Delete list"
            @click="handleDeleteList"
          >
            <TrashIcon class="size-4" />
          </button>
        </div>
      </div>

      <!-- Items -->
      <ul
        v-if="items.length > 0"
        class="divide-y divide-gray-100 dark:divide-stone-700"
      >
        <TaskItemRow
          v-for="item in items"
          :key="item.id"
          :item="item"
          @toggle="handleToggle"
          @delete="handleDeleteItem"
        />
      </ul>

      <!-- Add item input -->
      <div class="mt-3 flex items-center gap-2">
        <input
          v-model="newItemContent"
          type="text"
          placeholder="Add an item..."
          class="flex-1 rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-amber-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
          :disabled="isAddingItem"
          @keyup.enter="handleAddItem"
        />
        <button
          type="button"
          class="rounded-md bg-amber-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-700 disabled:opacity-50"
          :disabled="!newItemContent.trim() || isAddingItem"
          @click="handleAddItem"
        >
          Add
        </button>
      </div>

      <!-- Clear completed -->
      <div v-if="hasCompleted" class="mt-3">
        <button
          type="button"
          class="text-xs text-gray-400 hover:text-gray-600 dark:text-stone-500 dark:hover:text-stone-300"
          @click="handleClearCompleted"
        >
          Clear {{ completedItems.length }} completed
          {{ completedItems.length === 1 ? 'item' : 'items' }}
        </button>
      </div>
    </div>
  </div>
</template>
