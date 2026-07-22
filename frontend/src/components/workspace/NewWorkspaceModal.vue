<script setup lang="ts">
import { ref } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'
import { useWorkspaceStore } from '@/stores/workspace'
import { deviceTimezone } from '@/utils/timezone'
import { TEXT_LIMITS } from '@/constants/limits'

defineProps<{ open: boolean }>()
const emit = defineEmits<{ close: []; created: [workspaceId: string] }>()

const workspaceStore = useWorkspaceStore()

const name = ref('')
const creating = ref(false)
const createError = ref<string | null>(null)

// The layout mounts this only while open, so each open starts from the
// initial state above — no reset needed on the way in or out.
//
// Only the name is asked for. The zone starts as the creator's own, which is
// right nearly always and is a click away in the workspace's settings when
// it isn't — not worth a second field in the way of getting started.
async function submit(): Promise<void> {
  if (creating.value || name.value.trim().length === 0) return
  creating.value = true
  createError.value = null
  try {
    const { workspaceId } = await workspaceStore.createWorkspace(
      name.value.trim(),
      deviceTimezone()
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
  <BaseModal
    :open="open"
    title="New workspace"
    size="sm"
    @close="emit('close')"
  >
    <form @submit.prevent="submit">
      <FormInput
        id="new-workspace-name"
        v-model="name"
        label="Name"
        placeholder="Household, Ski trip crew, …"
        :maxlength="TEXT_LIMITS.name"
        required
      />

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
