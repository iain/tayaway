<script setup lang="ts">
import { computed } from 'vue'
import { Menu, MenuButton, MenuItems, MenuItem } from '@headlessui/vue'
import { EllipsisVerticalIcon } from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'
import { useMediaQuery } from '@/composables/useMediaQuery'

const props = defineProps<{
  canDelete?: boolean
  canClear?: boolean
}>()

const emit = defineEmits<{
  addChore: []
  autofill: []
  clearUpcoming: []
  deleteRoster: []
  manageChores: []
}>()

// Desktop lays "Auto-fill" and "Add chore" out in a row; the phone keeps only
// the primary "Add chore" visible. Everything else lives in the overflow menu,
// so each label renders exactly once and stays unique for the e2e suite
// (which runs desktop width).
const isDesktop = useMediaQuery('(min-width: 768px)')

type MenuAction = 'autofill' | 'manageChores' | 'clearUpcoming' | 'deleteRoster'

interface MenuEntry {
  label: string
  action: MenuAction
  danger?: boolean
}

// The trailing "…" marks the items that open a confirm dialog — the menu
// shows what's on offer before anything modal appears, so the destructive
// tail of the toolbar never has to be a lone red trash can.
const menuItems = computed<MenuEntry[]>(() => {
  const items: MenuEntry[] = []
  if (!isDesktop.value) {
    items.push({ label: 'Auto-fill', action: 'autofill' })
    items.push({ label: 'Manage chores', action: 'manageChores' })
  }
  if (props.canClear) {
    items.push({
      label: 'Clear upcoming assignments…',
      action: 'clearUpcoming',
    })
  }
  if (props.canDelete) {
    items.push({
      label: 'Delete roster…',
      action: 'deleteRoster',
      danger: true,
    })
  }
  return items
})

// vue's typed emit wants a literal event name per call, so spell the four out.
function choose(action: MenuAction) {
  if (action === 'autofill') {
    emit('autofill')
  } else if (action === 'manageChores') {
    emit('manageChores')
  } else if (action === 'clearUpcoming') {
    emit('clearUpcoming')
  } else {
    emit('deleteRoster')
  }
}
</script>

<template>
  <div class="flex items-center gap-2">
    <AppButton v-if="isDesktop" variant="secondary" @click="$emit('autofill')">
      Auto-fill
    </AppButton>
    <AppButton @click="$emit('addChore')">Add chore</AppButton>
    <Menu v-if="menuItems.length > 0" as="div" class="relative shrink-0">
      <MenuButton
        aria-label="More roster actions"
        class="text-ink-muted focus-visible:outline-focus hover:text-ink flex size-11 cursor-pointer items-center justify-center rounded-md hover:bg-black/5 focus-visible:outline-2 focus-visible:outline-offset-2 dark:hover:bg-white/10"
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
            v-for="item in menuItems"
            :key="item.action"
            v-slot="{ active }"
          >
            <button
              type="button"
              :class="[
                active ? 'bg-btn-secondary-fill' : '',
                item.danger ? 'text-state-danger-ink' : 'text-ink',
                'block w-full px-4 py-2.5 text-left text-sm',
              ]"
              @click="choose(item.action)"
            >
              {{ item.label }}
            </button>
          </MenuItem>
        </MenuItems>
      </transition>
    </Menu>
  </div>
</template>
