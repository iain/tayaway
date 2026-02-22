<script setup lang="ts">
import { ref, watchEffect } from 'vue'
import { storeToRefs } from 'pinia'
import { ClipboardDocumentListIcon, PlusIcon } from '@heroicons/vue/24/outline'
import { VueDraggable } from 'vue-draggable-plus'
import type { SortableEvent } from 'vue-draggable-plus'
import { useTaskListsStore, useNotificationsStore } from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useWorkspaceStore } from '@/stores/workspace'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import PrimaryButton from '@/components/common/PrimaryButton.vue'
import AddTaskListModal from '@/components/tasks/AddTaskListModal.vue'
import TaskListCard from '@/components/tasks/TaskListCard.vue'
import type { PoolTaskList } from '@/types/pool'

const taskListsStore = useTaskListsStore()
const pool = useObjectPoolStore()
const workspaceStore = useWorkspaceStore()
const { currentWorkspaceId } = storeToRefs(workspaceStore)

const isModalOpen = ref(false)
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

function openModal(): void {
  formError.value = null
  isModalOpen.value = true
}

function closeModal(): void {
  isModalOpen.value = false
}

async function handleSave(name: string): Promise<void> {
  formError.value = null
  isSubmitting.value = true

  try {
    const { queued } = await taskListsStore.createTaskList(name)
    isModalOpen.value = false
    if (queued) {
      const notifications = useNotificationsStore()
      notifications.showInfo('Task list will be created when back online')
    }
  } catch {
    formError.value = 'Failed to create task list'
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader title="Tasks" data-testid="page-title">
      <PrimaryButton data-testid="add-task-list-button" @click="openModal">
        <PlusIcon class="size-5" />
        New List
      </PrimaryButton>
    </PageHeader>

    <div
      v-if="formError"
      class="mb-4 rounded-md bg-red-900/50 p-4 text-red-400"
    >
      {{ formError }}
    </div>

    <EmptyState
      v-if="taskListsLocal.length === 0"
      :icon="ClipboardDocumentListIcon"
      heading="No task lists"
      description="Get started by creating a new task list."
    >
      <PrimaryButton @click="openModal">
        <PlusIcon class="size-5" />
        New List
      </PrimaryButton>
    </EmptyState>

    <VueDraggable
      v-else
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
        :task-list="taskList"
      />
    </VueDraggable>

    <AddTaskListModal
      :open="isModalOpen"
      :loading="isSubmitting"
      @close="closeModal"
      @save="handleSave"
    />
  </div>
</template>
