<script setup lang="ts">
import {
  ref,
  computed,
  watch,
  watchEffect,
  onMounted,
  onUnmounted,
  nextTick,
} from 'vue'
import { storeToRefs } from 'pinia'
import { ClipboardDocumentListIcon, PlusIcon } from '@heroicons/vue/24/outline'
import { VueDraggable } from 'vue-draggable-plus'
import type { SortableEvent } from 'vue-draggable-plus'
import { useTaskListsStore, useNotificationsStore } from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useWorkspaceStore } from '@/stores/workspace'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import AppButton from '@/components/common/AppButton.vue'
import AlertBox from '@/components/common/AlertBox.vue'
import TaskListCard from '@/components/tasks/TaskListCard.vue'
import { useTaskActions } from '@/composables/useTaskActions'
import type { PoolTaskList, PoolTaskItem } from '@/types/pool'

const taskListsStore = useTaskListsStore()
const pool = useObjectPoolStore()
const workspaceStore = useWorkspaceStore()
const { currentWorkspaceId } = storeToRefs(workspaceStore)

const { pendingNewList, resetNewList } = useTaskActions()

const showNewListInput = ref(false)
const newListName = ref('')
const newListInput = ref<HTMLInputElement | null>(null)

watch(pendingNewList, (val) => {
  if (val) {
    resetNewList()
    openNewListInput()
  }
})

const isSubmitting = ref(false)
const formError = ref<string | null>(null)

// Local sorted list for drag-and-drop (synced from pool)
const taskListsLocal = ref<PoolTaskList[]>([])

watchEffect(() => {
  taskListsLocal.value = pool
    .getAll('taskList')
    .filter((tl) => tl.workspaceId === currentWorkspaceId.value)
    .sort((a, b) => a.position - b.position)
})

// Keyboard navigation
const highlightedItemId = ref<string | null>(null)

interface TaskListCardExposed {
  focusInput(): void
  toggleItem(item: PoolTaskItem): void
  deleteItem(item: PoolTaskItem): void
}
const cardRefs = ref<Record<string, TaskListCardExposed>>({})

function setCardRef(id: string, el: unknown): void {
  if (el) {
    cardRefs.value[id] = el as TaskListCardExposed
  } else {
    delete cardRefs.value[id]
  }
}

const allItems = computed(() => {
  const result: PoolTaskItem[] = []
  for (const list of taskListsLocal.value) {
    const listItems = pool
      .getAll('taskItem')
      .filter((item) => item.taskListId === list.id)
      .sort((a, b) => a.position - b.position)
    result.push(...listItems)
  }
  return result
})

watch(allItems, (items) => {
  if (
    highlightedItemId.value &&
    !items.find((i) => i.id === highlightedItemId.value)
  ) {
    highlightedItemId.value = null
  }
})

function isInputActive(): boolean {
  const el = document.activeElement
  return (
    el instanceof HTMLInputElement ||
    el instanceof HTMLTextAreaElement ||
    (el instanceof HTMLElement && el.isContentEditable)
  )
}

async function handleKeydown(e: KeyboardEvent): Promise<void> {
  if (isInputActive()) return
  const items = allItems.value

  if (e.key === 'j') {
    e.preventDefault()
    if (items.length === 0) return
    if (highlightedItemId.value === null) {
      highlightedItemId.value = items[0]!.id
    } else {
      const idx = items.findIndex((item) => item.id === highlightedItemId.value)
      if (idx < items.length - 1) highlightedItemId.value = items[idx + 1]!.id
    }
    await nextTick()
    document
      .querySelector(`[data-item-id="${highlightedItemId.value}"]`)
      ?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  } else if (e.key === 'k') {
    e.preventDefault()
    if (items.length === 0) return
    if (highlightedItemId.value === null) {
      highlightedItemId.value = items[items.length - 1]!.id
    } else {
      const idx = items.findIndex((item) => item.id === highlightedItemId.value)
      if (idx > 0) highlightedItemId.value = items[idx - 1]!.id
    }
    await nextTick()
    document
      .querySelector(`[data-item-id="${highlightedItemId.value}"]`)
      ?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  } else if (e.key === ' ') {
    if (highlightedItemId.value === null) return
    e.preventDefault()
    const item = items.find((i) => i.id === highlightedItemId.value)
    if (!item) return
    cardRefs.value[item.taskListId]?.toggleItem(item)
  } else if (e.key === 'Backspace') {
    if (highlightedItemId.value === null) return
    e.preventDefault()
    const item = items.find((i) => i.id === highlightedItemId.value)
    if (!item) return
    const idx = items.indexOf(item)
    highlightedItemId.value = items[idx + 1]?.id ?? items[idx - 1]?.id ?? null
    cardRefs.value[item.taskListId]?.deleteItem(item)
  } else if (e.key === 'i') {
    e.preventDefault()
    if (highlightedItemId.value !== null) {
      const item = items.find((i) => i.id === highlightedItemId.value)
      if (item) {
        cardRefs.value[item.taskListId]?.focusInput()
        return
      }
    }
    const firstList = taskListsLocal.value[0]
    if (firstList) cardRefs.value[firstList.id]?.focusInput()
  }
}

onMounted(() => window.addEventListener('keydown', handleKeydown))
onUnmounted(() => window.removeEventListener('keydown', handleKeydown))

async function handleListDragEnd(event: SortableEvent) {
  const newIndex = event.newIndex
  if (newIndex === undefined) return

  const list = taskListsLocal.value
  const movedList = list[newIndex]
  if (!movedList) return

  const before = newIndex > 0 ? (list[newIndex - 1]?.position ?? null) : null
  const after =
    newIndex < list.length - 1 ? (list[newIndex + 1]?.position ?? null) : null

  await taskListsStore.repositionList(movedList.id, before, after)
}

async function openNewListInput(): Promise<void> {
  formError.value = null
  newListName.value = ''
  showNewListInput.value = true
  await nextTick()
  newListInput.value?.focus()
}

function cancelNewList(): void {
  showNewListInput.value = false
  newListName.value = ''
}

async function handleNewListSubmit(): Promise<void> {
  const name = newListName.value.trim()
  if (!name || isSubmitting.value) return

  formError.value = null
  isSubmitting.value = true

  try {
    const { listId, queued } = await taskListsStore.createTaskList(name)
    newListName.value = ''
    showNewListInput.value = false
    if (queued) {
      const notifications = useNotificationsStore()
      notifications.showInfo('Task list will be created when back online')
    }
    // Focus the new list's item input so the user can immediately add items
    await nextTick()
    cardRefs.value[listId]?.focusInput()
  } catch {
    formError.value = 'Failed to create task list'
  } finally {
    isSubmitting.value = false
  }
}

function handleNewListBlur(): void {
  if (!newListName.value.trim()) {
    cancelNewList()
  }
}
</script>

<template>
  <div>
    <PageHeader title="Tasks" data-testid="page-title">
      <AppButton data-testid="add-task-list-button" @click="openNewListInput">
        <PlusIcon class="size-5" />
        New List
      </AppButton>
    </PageHeader>

    <AlertBox v-if="formError" class="mb-4">
      {{ formError }}
    </AlertBox>

    <!-- Inline new list input -->
    <div v-if="showNewListInput" class="mb-6" data-testid="new-list-form">
      <form
        class="flex items-center gap-3"
        @submit.prevent="handleNewListSubmit"
      >
        <input
          ref="newListInput"
          v-model="newListName"
          type="text"
          placeholder="List name"
          aria-label="List name"
          data-testid="new-list-name-input"
          class="flex-1 rounded-md bg-gray-100 px-3 py-2 text-sm font-semibold text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:font-normal placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-focus dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
          :disabled="isSubmitting"
          @keyup.escape="cancelNewList"
          @blur="handleNewListBlur"
        />
        <AppButton
          type="submit"
          size="sm"
          data-testid="submit-button"
          :disabled="!newListName.trim()"
          :loading="isSubmitting"
          loading-label="Creating..."
        >
          Create
        </AppButton>
      </form>
    </div>

    <EmptyState
      v-if="taskListsLocal.length === 0 && !showNewListInput"
      :icon="ClipboardDocumentListIcon"
      heading="No task lists yet"
      description="Create a list to track what needs doing — packing, shopping, or anything your group needs to coordinate."
    >
      <AppButton @click="openNewListInput">
        <PlusIcon class="size-5" />
        New List
      </AppButton>
    </EmptyState>

    <VueDraggable
      v-else-if="taskListsLocal.length > 0"
      v-model="taskListsLocal"
      class="space-y-6"
      handle=".list-drag-handle"
      :animation="150"
      ghost-class="opacity-50"
      @end="handleListDragEnd"
    >
      <TaskListCard
        v-for="taskList in taskListsLocal"
        :key="taskList.id"
        :ref="(el) => setCardRef(taskList.id, el)"
        :task-list="taskList"
        :highlighted-item-id="highlightedItemId"
        @highlight="highlightedItemId = $event"
      />
    </VueDraggable>
  </div>
</template>
