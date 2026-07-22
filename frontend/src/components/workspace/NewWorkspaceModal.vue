<script setup lang="ts">
import { ref } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'
import TimezoneSelect from '@/components/form/TimezoneSelect.vue'
import { useWorkspaceStore } from '@/stores/workspace'

defineProps<{ open: boolean }>()
const emit = defineEmits<{ close: []; created: [workspaceId: string] }>()

const workspaceStore = useWorkspaceStore()

function deviceZone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone
}

const name = ref('')
const timezone = ref(deviceZone())
const creating = ref(false)
const createError = ref<string | null>(null)

// The layout mounts this only while open, so each open starts from the
// initial state above — no reset needed on the way in or out.
async function submit(): Promise<void> {
  if (creating.value || name.value.trim().length === 0) return
  creating.value = true
  createError.value = null
  try {
    const { workspaceId } = await workspaceStore.createWorkspace(
      name.value.trim(),
      timezone.value
    )
    emit('created', workspaceId)
    emit('close')
  } catch {
    createError.value = "Couldn't create the workspace. Try again."
  } finally {
    creating.value = false
  }
}
</script>

<template>
  <BaseModal :open="open" title="New workspace" @close="emit('close')">
    <form @submit.prevent="submit">
      <div class="flex flex-col gap-4">
        <FormInput
          id="new-workspace-name"
          v-model="name"
          label="Name"
          placeholder="Household, Ski trip crew, …"
          :maxlength="255"
          required
        />
        <TimezoneSelect
          id="new-workspace-timezone"
          v-model="timezone"
          label="Timezone"
          :auto-label="null"
        />
      </div>

      <p
        v-if="createError"
        role="alert"
        class="text-state-danger-ink mt-2 text-sm"
      >
        {{ createError }}
      </p>

      <FormActions
        submit-label="Create"
        loading-label="Creating..."
        submit-testid="create-workspace-button"
        :loading="creating"
        :disabled="name.trim().length === 0"
        @cancel="emit('close')"
      />
    </form>
  </BaseModal>
</template>
