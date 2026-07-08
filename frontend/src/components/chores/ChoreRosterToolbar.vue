<script setup lang="ts">
import { Menu, MenuButton, MenuItems, MenuItem } from '@headlessui/vue'
import { EllipsisVerticalIcon, TrashIcon } from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import { useMediaQuery } from '@/composables/useMediaQuery'

defineProps<{
  canDelete?: boolean
}>()

defineEmits<{
  addChore: []
  autofill: []
  deleteRoster: []
  manageChores: []
}>()

// Desktop lays every action out in a row; the phone keeps the primary "Add
// chore" visible and folds the rest (including mobile-only "Manage chores")
// into an overflow menu. One or the other renders, never both, so the toolbar's
// button labels stay unique for the e2e suite (which runs desktop width).
const isDesktop = useMediaQuery('(min-width: 768px)')
</script>

<template>
  <div v-if="isDesktop" class="flex items-center gap-2">
    <IconButton
      v-if="canDelete"
      label="Delete roster"
      @click="$emit('deleteRoster')"
    >
      <TrashIcon class="size-4 text-red-500 dark:text-red-400" />
    </IconButton>
    <AppButton variant="secondary" @click="$emit('autofill')">
      Auto-fill
    </AppButton>
    <AppButton @click="$emit('addChore')">Add chore</AppButton>
  </div>

  <div v-else class="flex items-center gap-2">
    <AppButton @click="$emit('addChore')">Add chore</AppButton>
    <Menu as="div" class="relative shrink-0">
      <MenuButton
        aria-label="More chore actions"
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
          class="bg-surface ring-ring-hairline absolute right-0 z-20 mt-1 w-48 origin-top-right rounded-md py-1 shadow-lg ring-1 focus:outline-hidden"
        >
          <MenuItem v-slot="{ active }">
            <button
              type="button"
              :class="[
                active ? 'bg-btn-secondary-fill' : '',
                'text-ink block w-full px-4 py-2.5 text-left text-sm',
              ]"
              @click="$emit('autofill')"
            >
              Auto-fill
            </button>
          </MenuItem>
          <MenuItem v-slot="{ active }">
            <button
              type="button"
              :class="[
                active ? 'bg-btn-secondary-fill' : '',
                'text-ink block w-full px-4 py-2.5 text-left text-sm',
              ]"
              @click="$emit('manageChores')"
            >
              Manage chores
            </button>
          </MenuItem>
          <MenuItem v-if="canDelete" v-slot="{ active }">
            <button
              type="button"
              :class="[
                active ? 'bg-btn-secondary-fill' : '',
                'text-state-danger-ink block w-full px-4 py-2.5 text-left text-sm',
              ]"
              @click="$emit('deleteRoster')"
            >
              Delete roster
            </button>
          </MenuItem>
        </MenuItems>
      </transition>
    </Menu>
  </div>
</template>
