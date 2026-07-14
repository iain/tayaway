<script setup lang="ts">
import { Menu, MenuButton, MenuItems, MenuItem } from '@headlessui/vue'
import { EllipsisVerticalIcon } from '@heroicons/vue/24/outline'

type RsvpActionKind =
  | 'attend'
  | 'decline'
  | 'set-dates'
  | 'change-dates'
  | 'rename'

interface RsvpAction {
  kind: RsvpActionKind
  label: string
  danger?: boolean
}

defineProps<{
  menuLabel: string
  actions: RsvpAction[]
}>()

const emit = defineEmits<{
  pick: [kind: RsvpActionKind]
}>()
</script>

<template>
  <Menu as="div" class="relative shrink-0">
    <MenuButton
      :aria-label="menuLabel"
      data-testid="rsvp-other-menu"
      class="text-ink-muted focus-visible:outline-focus hover:text-ink flex size-8 cursor-pointer items-center justify-center rounded-md hover:bg-black/5 focus-visible:outline-2 focus-visible:outline-offset-2 dark:hover:bg-white/10"
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
        class="bg-surface ring-ring-hairline absolute right-0 z-10 mt-1 w-48 origin-top-right rounded-md py-1 shadow-lg ring-1 focus:outline-hidden"
      >
        <MenuItem
          v-for="action in actions"
          :key="action.kind"
          v-slot="{ active }"
        >
          <button
            type="button"
            :class="[
              active ? 'bg-btn-secondary-fill' : '',
              action.danger ? 'text-state-danger-ink' : 'text-ink',
              'block w-full px-4 py-2 text-left text-sm',
            ]"
            @click="emit('pick', action.kind)"
          >
            {{ action.label }}
          </button>
        </MenuItem>
      </MenuItems>
    </transition>
  </Menu>
</template>
