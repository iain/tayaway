<script lang="ts">
export interface ActionMenuAction {
  label: string
  onPick: () => void
  danger?: boolean
  testid?: string
}
</script>

<script setup lang="ts">
import { ref, computed, useId, watch } from 'vue'
import { Menu, MenuButton, MenuItems, MenuItem } from '@headlessui/vue'
import { EllipsisVerticalIcon, XMarkIcon } from '@heroicons/vue/24/outline'
import { useMediaQuery } from '@/composables/useMediaQuery'

// The three-dots overflow menu: a Headless UI dropdown on desktop, a modal
// bottom sheet on touch-sized viewports. One trigger API for both — the
// consumer supplies actions (each carrying its own onPick handler) plus
// optional read-only meta lines ("Added by Daisy", "Completed Jan 3, 14:05")
// that render in a non-interactive block under the actions. Pass meta as a
// getter when the lines are costly to compute — it's only invoked once the
// menu is actually open.
//
// Accessibility notes:
//   - Desktop: Headless UI's Menu carries the full menu-button contract
//     (aria-haspopup/expanded, arrow keys, focus return on close).
//   - Mobile: a native <dialog> via showModal() gives us the focus trap,
//     Escape handling, and focus restore to the trigger for free. The sheet
//     always has a visible close button — swipe/scrim-only dismissal would
//     exclude keyboard and switch users. Rows are 44px tall tap targets and
//     the sheet pads itself past the home-indicator safe area.
const props = defineProps<{
  /** Accessible name for the trigger, e.g. "Options for Milk". */
  label: string
  /** Heading shown on the mobile sheet. */
  title: string
  actions: ActionMenuAction[]
  meta?: string[] | (() => string[])
  triggerTestid?: string
}>()

const emit = defineEmits<{
  /** Fires on mousedown of the trigger, before any focus/blur — lets a
   consumer cancel inline editing before the menu opens. */
  triggerMousedown: []
}>()

// Only read from the open panel/sheet, so a getter-shaped `meta` costs
// nothing until the menu is actually opened.
const metaLines = computed(() =>
  typeof props.meta === 'function' ? props.meta() : props.meta
)

// Tailwind `sm` — below it the dropdown would clip and fingers need bigger
// targets, so the sheet takes over.
const isDesktop = useMediaQuery('(min-width: 640px)')

const sheetOpen = ref(false)
// Latch that defers rendering the sheet's body until first open: one closed
// sheet is cheap, but one per list item adds thousands of hidden DOM nodes
// on exactly the viewports that can least afford them. Latched (not tied to
// sheetOpen) so the body stays in place during the close animation.
const hasOpened = ref(false)
const sheetRef = ref<HTMLDialogElement | null>(null)
const sheetTitleId = useId()

watch(sheetOpen, (open) => {
  if (open) {
    hasOpened.value = true
    sheetRef.value?.showModal()
  } else {
    sheetRef.value?.close()
  }
})

function pickFromSheet(action: ActionMenuAction): void {
  sheetOpen.value = false
  action.onPick()
}

// Native <dialog> reports backdrop clicks as clicks on the dialog element
// itself — anything inside the sheet targets a child instead.
function handleSheetClick(event: MouseEvent): void {
  if (event.target === sheetRef.value) {
    sheetOpen.value = false
  }
}
</script>

<template>
  <Menu v-if="isDesktop" as="div" class="relative shrink-0">
    <MenuButton
      :aria-label="label"
      :data-testid="triggerTestid"
      class="text-ink-muted focus-visible:outline-focus hover:text-ink flex size-8 cursor-pointer items-center justify-center rounded-md hover:bg-black/5 focus-visible:outline-2 focus-visible:outline-offset-2 dark:hover:bg-white/10"
      @mousedown="emit('triggerMousedown')"
    >
      <EllipsisVerticalIcon class="size-5" aria-hidden="true" />
    </MenuButton>
    <transition
      enter-active-class="transition ease-out duration-100"
      enter-from-class="transform opacity-0 scale-95"
      enter-to-class="transform opacity-100 scale-100"
      leave-active-class="transition ease-in duration-75"
      leave-from-class="transform opacity-100 scale-100"
      leave-to-class="transform opacity-0 scale-95"
    >
      <MenuItems
        class="bg-surface ring-ring-hairline absolute right-0 z-20 mt-1 w-56 origin-top-right rounded-md py-1 shadow-lg ring-1 focus:outline-hidden"
      >
        <MenuItem
          v-for="action in actions"
          :key="action.label"
          v-slot="{ active }"
        >
          <button
            type="button"
            :data-testid="action.testid"
            :class="[
              active ? 'bg-btn-secondary-fill' : '',
              action.danger ? 'text-state-danger-ink' : 'text-ink',
              'block w-full px-4 py-2 text-left text-sm',
            ]"
            @click="action.onPick()"
          >
            {{ action.label }}
          </button>
        </MenuItem>
        <div
          v-if="metaLines && metaLines.length > 0"
          class="border-line-faint mt-1 border-t px-4 pt-2 pb-1"
          data-testid="action-menu-meta"
        >
          <p
            v-for="line in metaLines"
            :key="line"
            class="text-ink-muted py-0.5 text-xs"
          >
            {{ line }}
          </p>
        </div>
      </MenuItems>
    </transition>
  </Menu>

  <div v-else class="shrink-0">
    <button
      type="button"
      :aria-label="label"
      aria-haspopup="dialog"
      :aria-expanded="sheetOpen"
      :data-testid="triggerTestid"
      class="text-ink-muted focus-visible:outline-focus hover:text-ink flex min-h-[44px] min-w-[44px] cursor-pointer items-center justify-center rounded-md hover:bg-black/5 focus-visible:outline-2 focus-visible:outline-offset-2 dark:hover:bg-white/10"
      @mousedown="emit('triggerMousedown')"
      @click="sheetOpen = true"
    >
      <EllipsisVerticalIcon class="size-5" aria-hidden="true" />
    </button>

    <dialog
      ref="sheetRef"
      :aria-labelledby="sheetTitleId"
      class="action-sheet bg-surface ring-line m-0 mt-auto w-full max-w-full rounded-t-2xl p-4 pb-[calc(1rem+env(safe-area-inset-bottom))] text-left shadow-xl ring-1 backdrop:bg-gray-500/85 dark:backdrop:bg-stone-900/80"
      data-testid="action-menu-sheet"
      @close="sheetOpen = false"
      @click="handleSheetClick"
    >
      <template v-if="hasOpened">
        <div
          class="bg-line mx-auto mb-3 h-1 w-10 rounded-full"
          aria-hidden="true"
        />
        <div class="mb-2 flex items-start justify-between gap-2">
          <h3
            :id="sheetTitleId"
            class="text-ink min-w-0 flex-1 truncate text-base font-semibold"
          >
            {{ title }}
          </h3>
          <button
            type="button"
            class="text-ink-muted hover:text-ink focus-visible:outline-focus -m-2 flex min-h-[44px] min-w-[44px] items-center justify-center rounded-md focus-visible:outline-2 focus-visible:outline-offset-2"
            @click="sheetOpen = false"
          >
            <span class="sr-only">Close</span>
            <XMarkIcon class="size-6" aria-hidden="true" />
          </button>
        </div>

        <div class="flex flex-col">
          <button
            v-for="action in actions"
            :key="action.label"
            type="button"
            :data-testid="action.testid"
            :class="[
              action.danger ? 'text-state-danger-ink' : 'text-ink',
              'hover:bg-btn-secondary-fill flex min-h-[44px] w-full items-center rounded-md px-3 text-left text-base',
            ]"
            @click="pickFromSheet(action)"
          >
            {{ action.label }}
          </button>
        </div>

        <div
          v-if="metaLines && metaLines.length > 0"
          class="border-line-faint mt-2 border-t px-3 pt-3"
          data-testid="action-menu-meta"
        >
          <p
            v-for="line in metaLines"
            :key="line"
            class="text-ink-muted py-0.5 text-sm"
          >
            {{ line }}
          </p>
        </div>
      </template>
    </dialog>
  </div>
</template>

<style scoped>
.action-sheet {
  opacity: 0;
  transform: translateY(100%);
  transition:
    opacity 200ms cubic-bezier(0.25, 1, 0.5, 1),
    transform 200ms cubic-bezier(0.25, 1, 0.5, 1),
    overlay 200ms allow-discrete,
    display 200ms allow-discrete;
}

.action-sheet[open] {
  opacity: 1;
  transform: translateY(0);
}

.action-sheet::backdrop {
  opacity: 0;
  transition:
    opacity 200ms cubic-bezier(0.25, 1, 0.5, 1),
    overlay 200ms allow-discrete,
    display 200ms allow-discrete;
}

.action-sheet[open]::backdrop {
  opacity: 1;
}

@starting-style {
  .action-sheet[open] {
    opacity: 0;
    transform: translateY(100%);
  }

  .action-sheet[open]::backdrop {
    opacity: 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .action-sheet,
  .action-sheet::backdrop {
    transition-duration: 0.01ms;
  }
}
</style>
