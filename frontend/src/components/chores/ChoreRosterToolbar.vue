<script setup lang="ts">
import { TrashIcon } from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'

defineEmits<{
  addChore: []
  autofill: []
  deleteRoster: []
}>()
</script>

<template>
  <div class="flex items-center gap-2">
    <IconButton label="Delete roster" @click="$emit('deleteRoster')">
      <TrashIcon class="size-4 text-red-500 dark:text-red-400" />
    </IconButton>
    <AppButton variant="secondary" @click="$emit('autofill')">
      Auto-fill
    </AppButton>
    <AppButton @click="$emit('addChore')">Add chore</AppButton>
  </div>
</template>
