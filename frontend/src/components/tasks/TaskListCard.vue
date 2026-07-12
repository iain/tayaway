<script setup lang="ts">
import { ref, computed, watchEffect, nextTick, onUnmounted, useId } from 'vue'
import { ChevronDownIcon } from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'
import ActionMenu from '@/components/common/ActionMenu.vue'
import type { ActionMenuAction } from '@/components/common/ActionMenu.vue'
import { VueDraggable } from 'vue-draggable-plus'
import type { SortableEvent } from 'vue-draggable-plus'
import {
  useTaskListsStore,
  useTaskItemsStore,
  useNotificationsStore,
} from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useUndoDelete } from '@/composables/useUndoDelete'
import { useMediaQuery } from '@/composables/useMediaQuery'
import { useMinuteTicker } from '@/composables/useMinuteTicker'
import { useTaskListPrefs } from '@/composables/useTaskListPrefs'
import TaskItemRow from './TaskItemRow.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import { groupTaskItems } from './groupTaskItems'
import { TEXT_LIMITS } from '@/constants/limits'
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
const { undoableDelete } = useUndoDelete()
const { now } = useMinuteTicker()

// Accordion state: persisted per user per list, so the lists you keep
// collapsed stay collapsed on the next visit. The panel is v-show (not
// v-if) so sink-animation timers and the FLIP wrapper survive a collapse.
const { isListCollapsed, setListCollapsed, toggleListCollapsed } =
  useTaskListPrefs()
const collapsed = computed(() => isListCollapsed(props.taskList.id))
const panelId = useId()

// History disclosure (completed >1h ago): closed by default every visit —
// it's an archive glance, not a working area.
const historyOpen = ref(false)
const historyPanelId = useId()

const newItemContent = ref('')
const isAddingItem = ref(false)
const newItemInput = ref<HTMLInputElement | null>(null)
const isRenaming = ref(false)
const renameValue = ref('')
const renameInput = ref<HTMLInputElement | null>(null)

// The add box hard-caps at TEXT_LIMITS.shortText; only surface a counter once
// someone pushes past ~80% so the compact input stays clean in normal use.
const showAddCount = computed(
  () => newItemContent.value.length >= TEXT_LIMITS.shortText * 0.8
)
const addCountColor = computed(() =>
  newItemContent.value.length >= TEXT_LIMITS.shortText
    ? 'text-state-danger-ink'
    : 'text-state-warning-ink'
)

// IDs optimistically hidden after "clear completed" — survives pool re-imports
// caused by concurrent in-flight addItem/updateItem responses arriving as microtasks
// before Vue flushes the DOM.
const clearedIds = ref(new Set<string>())

// IDs the user has toggled to "complete" in this component instance.
// Persists across pool re-imports so handleClearCompleted can find the right IDs
// even if an in-flight addItem response clears the pending completedAt update.
const localCompletedIds = ref(new Set<string>())

// Completed items you *just* tapped, held in their current slot for a beat so
// they don't jump out from under your finger. When the hold expires the id is
// released and the item animates (FLIP) down to the completed zone. Only your
// own taps are held — remote toggles and reloads sink immediately.
const SINK_HOLD_MS = 900
const SINK_SLIDE_MS = 200
const heldIds = ref<Set<string>>(new Set())
const sinkTimers = new Map<string, ReturnType<typeof setTimeout>>()
const listWrap = ref<HTMLElement | null>(null)
const reducedMotion = useMediaQuery('(prefers-reduced-motion: reduce)')
// Monotonic id so overlapping sink animations don't clear each other's rows.
let flipRunId = 0

// Local sorted list for drag-and-drop (synced from pool).
// Uses watchEffect (not computed) because VueDraggable needs a writable v-model.
// Items completed over an hour ago split off into the History section below
// the list; `now` comes from the shared minute ticker so items age into
// History live, without a reload.
const itemsLocal = ref<PoolTaskItem[]>([])
const historyItems = ref<PoolTaskItem[]>([])

watchEffect(() => {
  const grouped = groupTaskItems(
    pool
      .getAll('taskItem')
      .filter(
        (item) =>
          item.taskListId === props.taskList.id &&
          !clearedIds.value.has(item.id)
      ),
    now.value,
    heldIds.value
  )
  itemsLocal.value = grouped.current
  historyItems.value = grouped.history
})

// FLIP: run `mutate` (which reorders the list), then slide every row that moved
// from its old position to its new one. Animates both the sinking item and the
// rows closing the gap above it. Reduced-motion just reorders.
async function animateReorder(mutate: () => void): Promise<void> {
  const container = listWrap.value
  if (!container || reducedMotion.value) {
    mutate()
    return
  }
  const rowsBefore = Array.from(
    container.querySelectorAll<HTMLElement>('[data-item-id]')
  )
  const firstTop = new Map<string, number>()
  for (const el of rowsBefore) {
    firstTop.set(el.dataset.itemId!, el.getBoundingClientRect().top)
  }

  mutate()
  await nextTick()

  // Tag every animated row with this run's id. If a later, overlapping sink
  // takes a shared row over, it re-tags it — so this run's cleanup below skips
  // rows the newer run is still animating instead of snapping them mid-slide.
  const runId = String(++flipRunId)
  const rowsAfter = Array.from(
    container.querySelectorAll<HTMLElement>('[data-item-id]')
  )
  const moved: HTMLElement[] = []
  for (const el of rowsAfter) {
    const prev = firstTop.get(el.dataset.itemId!)
    if (prev === undefined) continue
    const delta = prev - el.getBoundingClientRect().top
    if (!delta) continue
    el.dataset.flipRun = runId
    el.style.transition = 'none'
    el.style.transform = `translateY(${delta}px)`
    moved.push(el)
  }
  if (moved.length === 0) return

  // Force the inverted position to commit before starting the transition.
  void container.getBoundingClientRect()
  requestAnimationFrame(() => {
    for (const el of moved) {
      el.style.transition = `transform ${SINK_SLIDE_MS}ms ease`
      el.style.transform = ''
    }
    setTimeout(() => {
      for (const el of moved) {
        if (el.dataset.flipRun !== runId) continue
        el.style.transition = ''
        el.style.transform = ''
        delete el.dataset.flipRun
      }
    }, SINK_SLIDE_MS + 50)
  })
}

// Drop the hold on an id (re-sorts it into the completed zone). `animate`
// controls whether the move slides or snaps.
function releaseHold(id: string, animate: boolean): void {
  const timer = sinkTimers.get(id)
  if (timer) {
    clearTimeout(timer)
    sinkTimers.delete(id)
  }
  if (!heldIds.value.has(id)) return
  const drop = (): void => {
    const next = new Set(heldIds.value)
    next.delete(id)
    heldIds.value = next
  }
  if (animate) {
    void animateReorder(drop)
  } else {
    drop()
  }
}

onUnmounted(() => {
  for (const timer of sinkTimers.values()) clearTimeout(timer)
  sinkTimers.clear()
})

const items = itemsLocal

// Held items are still displayed in the active zone during the ~900ms hold, so
// they don't count toward the progress tally or the "Clear completed" sweep
// until they've actually sunk — the counter and the visible list stay in sync.
// History items are completed by definition, so they count toward both the
// tally and the sweep.
const completedItems = computed(() => [
  ...items.value.filter(
    (i) => i.completedAt !== null && !heldIds.value.has(i.id)
  ),
  ...historyItems.value,
])
const hasCompleted = computed(() => completedItems.value.length > 0)
const totalCount = computed(
  () => items.value.length + historyItems.value.length
)

const listMenuActions = computed<ActionMenuAction[]>(() => {
  const actions: ActionMenuAction[] = []
  if (hasCompleted.value) {
    actions.push({
      label: `Clear ${completedItems.value.length} completed`,
      testid: 'clear-completed-button',
      onPick: () => void handleClearCompleted(),
    })
  }
  actions.push(
    {
      label: 'Rename list',
      testid: 'rename-list-button',
      onPick: () => void startRename(),
    },
    {
      label: 'Delete list',
      danger: true,
      testid: 'delete-list-button',
      onPick: handleDeleteList,
    }
  )
  return actions
})

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
    // Hold in place, then animate down to the completed zone.
    heldIds.value = new Set(heldIds.value).add(item.id)
    const timer = sinkTimers.get(item.id)
    if (timer) clearTimeout(timer)
    sinkTimers.set(
      item.id,
      setTimeout(() => releaseHold(item.id, true), SINK_HOLD_MS)
    )
  } else {
    localCompletedIds.value.delete(item.id)
    // Un-checking cancels a pending sink; the item just stays where it is.
    releaseHold(item.id, false)
  }
  try {
    await taskItemsStore.updateItem(props.taskList.id, item.id, {
      completed: completing,
    })
  } catch {
    // error shown via store — undo local tracking
    if (completing) {
      localCompletedIds.value.delete(item.id)
      releaseHold(item.id, false)
    } else {
      localCompletedIds.value.add(item.id)
    }
  }
}

function handleDeleteItem(item: PoolTaskItem): void {
  undoableDelete({
    objectType: 'taskItem',
    objectId: item.id,
    message: 'Item deleted',
    apiPath: `/task-lists/${props.taskList.id}/items/${item.id}`,
  })
}

async function handleEditItem(
  item: PoolTaskItem,
  content: string
): Promise<void> {
  try {
    await taskItemsStore.updateItem(props.taskList.id, item.id, { content })
  } catch {
    // error shown via store
  }
}

async function handleClearCompleted(): Promise<void> {
  // Merge pool-derived completed IDs with locally-tracked ones. The local set
  // covers the race where an in-flight addItem response clears the pending
  // completedAt update before the click handler runs, leaving completedItems empty.
  // Held items (mid-sink, still shown as active) are excluded so clearing never
  // scoops one out of the middle of the list.
  const poolIds = completedItems.value.map((i) => i.id)
  const allIds = [...new Set([...poolIds, ...localCompletedIds.value])].filter(
    (id) => !heldIds.value.has(id)
  )
  for (const id of allIds) {
    localCompletedIds.value.delete(id)
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

// Focus explicitly: the rename action now arrives via the overflow menu,
// which restores focus to its trigger on close — without this the input
// would render unfocused.
async function startRename(): Promise<void> {
  renameValue.value = props.taskList.name
  isRenaming.value = true
  await nextTick()
  renameInput.value?.focus()
  renameInput.value?.select()
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

function handleDeleteList(): void {
  undoableDelete({
    objectType: 'taskList',
    objectId: props.taskList.id,
    message: 'List deleted',
    apiPath: `/task-lists/${props.taskList.id}`,
  })
}

defineExpose({
  focusInput(): void {
    // A collapsed list has no visible input — expand it first ("i" shortcut
    // and the post-create focus both land here).
    if (collapsed.value) {
      setListCollapsed(props.taskList.id, false)
      void nextTick(() => newItemInput.value?.focus())
    } else {
      newItemInput.value?.focus()
    }
  },
  toggleItem(item: PoolTaskItem): void {
    void handleToggle(item)
  },
  deleteItem(item: PoolTaskItem): void {
    handleDeleteItem(item)
  },
})
</script>

<template>
  <BaseCard data-testid="task-list-card">
    <div class="px-4 py-4 sm:px-6">
      <!-- Header -->
      <div
        class="flex items-center justify-between gap-2"
        :class="collapsed ? '' : 'mb-3'"
      >
        <span
          class="list-drag-handle text-ink-muted hover:text-ink cursor-grab touch-none"
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
            ref="renameInput"
            v-model="renameValue"
            type="text"
            data-testid="rename-list-input"
            :maxlength="TEXT_LIMITS.name"
            class="bg-surface-sunken text-ink outline-line focus:outline-focus min-w-0 flex-1 rounded-md px-2 py-1.5 text-base font-semibold outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2"
            @keyup.enter="commitRename"
            @keyup.escape="isRenaming = false"
            @blur="commitRename"
          />
        </div>
        <!-- The heading doubles as the accordion toggle (disclosure pattern:
             button with aria-expanded/aria-controls inside the heading). -->
        <h2 v-else class="min-w-0 flex-1 text-base font-semibold">
          <button
            type="button"
            data-testid="collapse-list-button"
            class="text-ink focus-visible:outline-focus flex w-full min-w-0 cursor-pointer items-center gap-1.5 rounded text-left focus-visible:outline-2 focus-visible:outline-offset-2"
            :aria-expanded="!collapsed"
            :aria-controls="panelId"
            :title="taskList.name"
            @click="toggleListCollapsed(taskList.id)"
          >
            <ChevronDownIcon
              class="text-ink-muted size-4 shrink-0 transition-transform"
              :class="collapsed ? '-rotate-90' : ''"
              aria-hidden="true"
            />
            <span class="min-w-0 truncate">{{ taskList.name }}</span>
          </button>
        </h2>

        <div class="flex shrink-0 items-center gap-1">
          <span
            v-if="totalCount > 0"
            class="text-meta text-ink-muted mr-1 tabular-nums"
            data-testid="task-list-progress"
            aria-label="Completed items"
          >
            {{ completedItems.length }}/{{ totalCount }}
          </span>
          <ActionMenu
            label="List options"
            :title="taskList.name"
            :actions="listMenuActions"
            trigger-testid="list-menu-button"
          />
        </div>
      </div>

      <!-- Accordion panel. v-show (not v-if) keeps sink timers, drag state,
           and the FLIP wrapper alive across a collapse. -->
      <div v-show="!collapsed" :id="panelId">
        <!-- Items (always rendered so empty lists can receive cross-list drops).
             The wrapper gives the sink FLIP a stable element to measure rows in. -->
        <div ref="listWrap">
          <VueDraggable
            v-model="itemsLocal"
            tag="ul"
            data-testid="task-items-list"
            class="divide-line-faint divide-y"
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
              @edit="handleEditItem"
              @highlight="emit('highlight', $event.id)"
            />
          </VueDraggable>
        </div>

        <!-- Items checked off more than an hour ago live here, out of the way
             of the active shopping flow but recoverable with one tap. -->
        <div
          v-if="historyItems.length > 0"
          class="border-line-faint mt-2 border-t pt-1"
        >
          <button
            type="button"
            data-testid="history-toggle"
            class="text-ink-muted hover:text-ink focus-visible:outline-focus flex min-h-[44px] w-full cursor-pointer items-center gap-1.5 rounded text-left text-sm focus-visible:outline-2 focus-visible:outline-offset-2"
            :aria-expanded="historyOpen"
            :aria-controls="historyPanelId"
            @click="historyOpen = !historyOpen"
          >
            <ChevronDownIcon
              class="size-4 shrink-0 transition-transform"
              :class="historyOpen ? '' : '-rotate-90'"
              aria-hidden="true"
            />
            History ({{ historyItems.length }})
          </button>
          <ul
            v-show="historyOpen"
            :id="historyPanelId"
            data-testid="history-items-list"
            class="divide-line-faint divide-y"
          >
            <TaskItemRow
              v-for="item in historyItems"
              :key="item.id"
              :item="item"
              in-history
              :highlighted="item.id === highlightedItemId"
              @toggle="handleToggle"
              @delete="handleDeleteItem"
              @edit="handleEditItem"
              @highlight="emit('highlight', $event.id)"
            />
          </ul>
        </div>

        <!-- Add item input: sticky to the bottom of the card so it stays
             thumb-reachable while scrolling a long list (shopping-trip flow).
             The bg covers items scrolling underneath; 16px font stops iOS
             from zooming the page on focus. -->
        <div
          class="bg-surface border-line-faint sticky bottom-0 z-10 -mx-4 mt-3 border-t px-4 pt-3 pb-1 sm:-mx-6 sm:px-6"
        >
          <div class="flex items-center gap-2">
            <input
              ref="newItemInput"
              v-model="newItemContent"
              type="text"
              placeholder="Add an item..."
              :maxlength="TEXT_LIMITS.shortText"
              class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder focus:outline-focus min-w-0 flex-1 rounded-md px-3 py-2 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2"
              :disabled="isAddingItem"
              @keyup.enter="handleAddItem"
              @keyup.escape="newItemInput?.blur()"
            />
            <AppButton
              :disabled="!newItemContent.trim() || isAddingItem"
              @click="handleAddItem"
            >
              Add
            </AppButton>
          </div>
          <p
            v-if="showAddCount"
            class="text-meta mt-1 text-right tabular-nums"
            :class="addCountColor"
          >
            {{ newItemContent.length }}/{{ TEXT_LIMITS.shortText }}
          </p>
        </div>
      </div>
    </div>
  </BaseCard>
</template>
