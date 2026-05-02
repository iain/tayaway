<script setup lang="ts">
import { ref, nextTick } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { BanknotesIcon } from '@heroicons/vue/24/outline'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)

const editing = ref(false)
const saving = ref(false)
const editIban = ref('')
const editInputRef = ref<HTMLInputElement | null>(null)

async function openEditor(): Promise<void> {
  editing.value = true
  editIban.value = ''
  await nextTick()
  editInputRef.value?.focus()
}

function cancelEdit(): void {
  editing.value = false
}

async function saveIban(): Promise<void> {
  if (saving.value || !editIban.value.trim()) return
  saving.value = true
  try {
    await authStore.updateProfile({ iban: editIban.value.trim() })
    editing.value = false
  } catch {
    // Error handled by mutation/toast
  } finally {
    saving.value = false
  }
}

async function removeIban(): Promise<void> {
  saving.value = true
  try {
    await authStore.updateProfile({ iban: '' })
    editing.value = false
  } catch {
    // Error handled by mutation/toast
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <BaseCard padded>
      <SectionHeading :icon="BanknotesIcon" title="Payment" />

      <p class="mb-2 text-sm text-gray-500 dark:text-stone-400">
        Adding your IBAN lets others pay you with a single QR code scan when
        settling shared expenses. Your IBAN is stored securely and never shared
        with other members &mdash; it is only used server-side to generate
        payment QR codes.
      </p>

      <dl class="divide-y divide-gray-200 dark:divide-stone-700">
        <DefinitionRow
          label="IBAN"
          value-class="truncate font-mono"
          edit-label="Edit IBAN"
          edit-testid="edit-iban-button"
          :editing="editing"
          @edit="openEditor"
        >
          {{ user?.iban ?? 'Not set' }}
          <template #editor>
            <div>
              <form class="flex items-center gap-2" @submit.prevent="saveIban">
                <input
                  ref="editInputRef"
                  v-model="editIban"
                  type="text"
                  aria-label="IBAN"
                  autocomplete="off"
                  placeholder="NL00 BANK 0000 0000 00"
                  :maxlength="34"
                  :disabled="saving"
                  class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 font-mono text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:font-mono placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
                  @keyup.escape="cancelEdit"
                />
                <AppButton
                  type="submit"
                  size="sm"
                  :disabled="!editIban.trim()"
                  :loading="saving"
                >
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="saving"
                  @click="cancelEdit"
                >
                  Cancel
                </TextButton>
              </form>
              <TextButton
                v-if="user?.iban"
                variant="danger"
                class="mt-2"
                :disabled="saving"
                @click="removeIban"
              >
                Remove IBAN
              </TextButton>
            </div>
          </template>
        </DefinitionRow>
      </dl>
    </BaseCard>
  </div>
</template>
