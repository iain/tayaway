<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { Cog6ToothIcon } from '@heroicons/vue/24/outline'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'
import TimezoneSelect from '@/components/form/TimezoneSelect.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import { useWorkspaceStore } from '@/stores/workspace'
import { useObjectPoolStore } from '@/stores/objectPool'

const route = useRoute()
const workspaceStore = useWorkspaceStore()
const pool = useObjectPoolStore()

const workspaceId = computed(() => String(route.params.id ?? ''))
const workspace = computed(() => pool.get('workspace', workspaceId.value))

const name = ref('')
const timezone = ref('')
const saving = ref(false)
const saveError = ref<string | null>(null)

// Reseed whenever the route points at a different workspace, or the stored
// values change under us (another admin renaming it, our own save landing).
// Skipped mid-save so the server echo doesn't yank the field the user is
// still typing in.
watch(
  workspace,
  (ws) => {
    if (!ws || saving.value) return
    name.value = ws.name
    timezone.value = ws.timezone
  },
  { immediate: true }
)

const dirty = computed(
  () =>
    workspace.value !== undefined &&
    (name.value !== workspace.value.name ||
      timezone.value !== workspace.value.timezone)
)

const canSave = computed(() => dirty.value && name.value.trim().length > 0)

async function save(): Promise<void> {
  if (!canSave.value || saving.value) return
  saving.value = true
  saveError.value = null
  try {
    await workspaceStore.updateWorkspace(workspaceId.value, {
      name: name.value.trim(),
      timezone: timezone.value,
    })
  } catch {
    saveError.value = "Couldn't save. Try again."
  } finally {
    saving.value = false
  }
}

function reset(): void {
  if (!workspace.value) return
  name.value = workspace.value.name
  timezone.value = workspace.value.timezone
  saveError.value = null
}
</script>

<template>
  <div>
    <SectionHeading :icon="Cog6ToothIcon" title="General" />
    <BaseCard padded>
      <EmptyState
        v-if="!workspace"
        :icon="Cog6ToothIcon"
        heading="Workspace not found"
        description="You may no longer be a member of it."
      />
      <form v-else data-testid="workspace-general-form" @submit.prevent="save">
        <div class="flex flex-col gap-4">
          <FormInput
            id="workspace-name"
            v-model="name"
            label="Workspace name"
            :maxlength="255"
            required
          />
          <TimezoneSelect
            id="workspace-timezone"
            v-model="timezone"
            label="Timezone"
            :auto-label="null"
          />
          <p class="text-ink-muted text-meta">
            The group's home zone. Events fall back to it when they have no
            location of their own.
          </p>
        </div>

        <p
          v-if="saveError"
          role="alert"
          class="text-state-danger-ink mt-2 text-sm"
        >
          {{ saveError }}
        </p>

        <FormActions
          :loading="saving"
          :disabled="!canSave"
          submit-testid="save-workspace-button"
          @cancel="reset"
        />
      </form>
    </BaseCard>
  </div>
</template>
