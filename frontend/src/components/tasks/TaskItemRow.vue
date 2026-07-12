<script setup lang="ts">
import { ref, nextTick } from 'vue'
import ActionMenu from '@/components/common/ActionMenu.vue'
import type { ActionMenuAction } from '@/components/common/ActionMenu.vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useLocale } from '@/composables/useLocale'
import { getMemberName } from '@/utils/member'
import { formatDateTime } from '@/utils/date'
import { TEXT_LIMITS } from '@/constants/limits'
import type { PoolTaskItem } from '@/types/pool'

const props = defineProps<{
  item: PoolTaskItem
  highlighted?: boolean
  /** History rows aren't draggable — their order is completion time. */
  inHistory?: boolean
}>()

const emit = defineEmits<{
  toggle: [item: PoolTaskItem]
  delete: [item: PoolTaskItem]
  edit: [item: PoolTaskItem, content: string]
  highlight: [item: PoolTaskItem]
}>()

const pool = useObjectPoolStore()
const { locale } = useLocale()

const isEditing = ref(false)
const editValue = ref('')
const editInput = ref<HTMLInputElement | null>(null)

const menuActions: ActionMenuAction[] = [
  {
    label: 'Delete item',
    danger: true,
    testid: 'delete-item-button',
    onPick: () => emit('delete', props.item),
  },
]

// Who added it and when, plus the completion moment for checked items —
// surfaced in the overflow menu so the row itself stays a clean tap target.
// A getter (not a computed bound into the row) so the member lookup and
// date formatting only run once the menu is opened, not on every row render.
function menuMeta(): string[] {
  const lines = [
    `Added by ${getMemberName(props.item.userId, pool)}`,
    `Added ${formatDateTime(props.item.createdAt, locale.value)}`,
  ]
  if (props.item.completedAt) {
    lines.push(
      `Completed ${formatDateTime(props.item.completedAt, locale.value)}`
    )
  }
  return lines
}

async function startEdit(): Promise<void> {
  editValue.value = props.item.content
  isEditing.value = true
  await nextTick()
  editInput.value?.focus()
  editInput.value?.select()
}

function commitEdit(): void {
  if (!isEditing.value) return
  isEditing.value = false
  const content = editValue.value.trim()
  // Compare against the trimmed stored value so merely opening and closing the
  // editor on an item with surrounding whitespace doesn't fire a no-op rewrite.
  if (content && content !== props.item.content.trim()) {
    emit('edit', props.item, content)
  }
}

function cancelEdit(): void {
  isEditing.value = false
}
</script>

<template>
  <li
    class="-mx-2 flex min-h-[44px] items-center gap-2 rounded px-2 py-1.5 sm:gap-3"
    :class="highlighted ? 'bg-surface-sunken' : ''"
    :data-item-id="item.id"
    :data-highlighted="highlighted ? 'true' : undefined"
    data-testid="task-item-row"
    @mouseenter="emit('highlight', item)"
  >
    <span
      v-if="!inHistory"
      class="item-drag-handle text-ink-muted hover:text-ink -m-1 shrink-0 cursor-grab touch-none p-1"
      data-testid="task-item-drag-handle"
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="size-4"
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

    <!-- Bigger tap target than the checkbox itself, but does NOT cover the text.
         aria-label carries the item content so each checkbox is identifiable to
         a screen reader (the content is a separate button, not in the label). -->
    <label class="-m-1 shrink-0 cursor-pointer p-1">
      <input
        type="checkbox"
        :checked="!!item.completedAt"
        :aria-label="`Mark ${item.content} complete`"
        class="size-6 cursor-pointer accent-rose-500"
        @change="emit('toggle', item)"
      />
    </label>

    <input
      v-if="isEditing"
      ref="editInput"
      v-model="editValue"
      type="text"
      data-testid="task-item-edit-input"
      :maxlength="TEXT_LIMITS.shortText"
      class="bg-surface-sunken text-ink outline-line focus:outline-focus min-w-0 flex-1 rounded-md px-2 py-1.5 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2"
      @keyup.enter="commitEdit"
      @keyup.escape="cancelEdit"
      @blur="commitEdit"
    />
    <button
      v-else
      type="button"
      data-testid="task-item-content"
      class="min-w-0 flex-1 py-1 text-left text-base break-words hyphens-auto"
      :class="item.completedAt ? 'text-ink-muted line-through' : 'text-ink'"
      :data-completed="item.completedAt ? 'true' : undefined"
      @click="startEdit"
    >
      {{ item.content }}
    </button>

    <!-- @trigger-mousedown cancels an in-progress inline edit before the
         input's blur can commit, so no spurious content update races the
         action picked from the menu. -->
    <ActionMenu
      :label="`Options for ${item.content}`"
      :title="item.content"
      :actions="menuActions"
      :meta="menuMeta"
      trigger-testid="item-menu-button"
      @trigger-mousedown="cancelEdit"
    />
  </li>
</template>
