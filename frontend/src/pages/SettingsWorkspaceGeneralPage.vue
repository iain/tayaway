<script setup lang="ts">
import { computed, nextTick, ref, useTemplateRef } from 'vue'
import { useRoute } from 'vue-router'
import { Cog6ToothIcon } from '@heroicons/vue/24/outline'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import TimezoneSelect from '@/components/form/TimezoneSelect.vue'
import { useWorkspaceStore } from '@/stores/workspace'
import { useObjectPoolStore } from '@/stores/objectPool'
import { formatZoneName } from '@/utils/timezone'
import { TEXT_LIMITS } from '@/constants/limits'

type WorkspaceField = 'name' | 'timezone'

const route = useRoute()
const workspaceStore = useWorkspaceStore()
const pool = useObjectPoolStore()

const workspaceId = computed(() => String(route.params.id ?? ''))
const workspace = computed(() => pool.get('workspace', workspaceId.value))

// Same per-field editing model as the profile and payment pages: the value
// reads as text until you click it, and each field saves on its own.
const editingFields = ref(new Set<WorkspaceField>())
const savingFields = ref(new Set<WorkspaceField>())
const saveErrors = ref(new Map<WorkspaceField, string>())

const editName = ref('')
const editTimezone = ref('')

const nameInputRef = useTemplateRef<HTMLInputElement>('nameInputRef')
const timezoneRef =
  useTemplateRef<InstanceType<typeof TimezoneSelect>>('timezoneRef')

const canSaveName = computed(() => editName.value.trim().length > 0)

async function openField(field: WorkspaceField): Promise<void> {
  if (editingFields.value.has(field)) return
  saveErrors.value.delete(field)
  if (field === 'name') {
    editName.value = workspace.value?.name ?? ''
  } else {
    editTimezone.value = workspace.value?.timezone ?? ''
  }
  editingFields.value.add(field)
  await nextTick()
  if (field === 'name') {
    nameInputRef.value?.focus()
  } else {
    timezoneRef.value?.focus()
  }
}

function cancelEdit(field: WorkspaceField): void {
  editingFields.value.delete(field)
  saveErrors.value.delete(field)
}

async function persist(
  field: WorkspaceField,
  changes: { name?: string; timezone?: string }
): Promise<void> {
  if (savingFields.value.has(field)) return
  savingFields.value.add(field)
  saveErrors.value.delete(field)
  try {
    await workspaceStore.updateWorkspace(workspaceId.value, changes)
    editingFields.value.delete(field)
  } catch {
    saveErrors.value.set(field, "Couldn't save. Try again.")
  } finally {
    savingFields.value.delete(field)
  }
}

function saveName(): Promise<void> {
  if (!canSaveName.value) return Promise.resolve()
  return persist('name', { name: editName.value.trim() })
}

function saveTimezone(): Promise<void> {
  return persist('timezone', { timezone: editTimezone.value })
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
      <dl v-else class="divide-line divide-y" data-testid="workspace-general">
        <DefinitionRow
          label="Name"
          value-class="truncate"
          edit-label="Edit workspace name"
          edit-testid="edit-workspace-name-button"
          :editing="editingFields.has('name')"
          @edit="openField('name')"
        >
          {{ workspace.name }}
          <template #editor>
            <div>
              <form
                class="flex flex-wrap items-center gap-2"
                :aria-busy="savingFields.has('name')"
                @submit.prevent="saveName"
              >
                <input
                  ref="nameInputRef"
                  v-model="editName"
                  type="text"
                  aria-label="Workspace name"
                  :maxlength="TEXT_LIMITS.name"
                  :disabled="savingFields.has('name')"
                  class="bg-surface-sunken text-ink outline-line placeholder:text-ink-placeholder focus:outline-focus min-w-0 flex-1 rounded-md px-3 py-1.5 text-base outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2 sm:text-sm/6"
                  @keyup.escape="cancelEdit('name')"
                />
                <AppButton
                  type="submit"
                  size="sm"
                  data-testid="save-workspace-name"
                  :disabled="!canSaveName"
                  :loading="savingFields.has('name')"
                >
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="savingFields.has('name')"
                  @click="cancelEdit('name')"
                >
                  Cancel
                </TextButton>
              </form>
              <p
                v-if="saveErrors.get('name')"
                role="alert"
                class="text-state-danger-ink mt-1 text-sm"
              >
                {{ saveErrors.get('name') }}
              </p>
            </div>
          </template>
        </DefinitionRow>

        <DefinitionRow
          label="Time zone"
          value-class="truncate"
          edit-label="Edit time zone"
          edit-testid="edit-workspace-timezone-button"
          :editing="editingFields.has('timezone')"
          @edit="openField('timezone')"
        >
          {{ formatZoneName(workspace.timezone) }}
          <template #editor>
            <!-- A form so Enter saves, as it does in the name editor. The
                 first Enter belongs to the combobox (it picks the highlighted
                 zone); once the list is closed the next one submits. -->
            <form
              :aria-busy="savingFields.has('timezone')"
              @submit.prevent="saveTimezone"
            >
              <TimezoneSelect
                id="workspace-timezone"
                ref="timezoneRef"
                v-model="editTimezone"
                label="Time zone"
                :auto-label="null"
                hide-label
                :disabled="savingFields.has('timezone')"
              />
              <p class="text-ink-muted text-meta mt-1">
                The group's home zone. Events fall back to it when they have no
                location of their own.
              </p>
              <div class="mt-2 flex flex-wrap items-center gap-2">
                <AppButton
                  type="submit"
                  size="sm"
                  data-testid="save-workspace-timezone"
                  :loading="savingFields.has('timezone')"
                >
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="savingFields.has('timezone')"
                  @click="cancelEdit('timezone')"
                >
                  Cancel
                </TextButton>
              </div>
              <p
                v-if="saveErrors.get('timezone')"
                role="alert"
                class="text-state-danger-ink mt-1 text-sm"
              >
                {{ saveErrors.get('timezone') }}
              </p>
            </form>
          </template>
        </DefinitionRow>
      </dl>
    </BaseCard>
  </div>
</template>
