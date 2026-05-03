<script setup lang="ts">
import { ref, computed, nextTick, useTemplateRef } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { BanknotesIcon, XCircleIcon } from '@heroicons/vue/24/outline'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import TextButton from '@/components/common/TextButton.vue'
import { formatIban, normalizeIban, validateIban } from '@/utils/iban'

type PaymentField = 'iban' | 'holderName'

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)

const editingFields = ref(new Set<PaymentField>())
const savingFields = ref(new Set<PaymentField>())

const editIban = ref('')
const editHolderName = ref('')

const ibanInputRef = useTemplateRef<HTMLInputElement>('ibanInputRef')
const holderNameInputRef =
  useTemplateRef<HTMLInputElement>('holderNameInputRef')

const ibanError = computed(() => validateIban(editIban.value))
const canSaveIban = computed(
  () => normalizeIban(editIban.value).length > 0 && ibanError.value === null
)
const canSaveHolderName = computed(() => editHolderName.value.trim().length > 0)

async function openIbanEditor(): Promise<void> {
  if (editingFields.value.has('iban')) return
  editIban.value = ''
  editingFields.value.add('iban')
  await nextTick()
  ibanInputRef.value?.focus()
}

async function openHolderNameEditor(): Promise<void> {
  if (editingFields.value.has('holderName')) return
  editHolderName.value = user.value?.ibanHolderName ?? ''
  editingFields.value.add('holderName')
  await nextTick()
  holderNameInputRef.value?.focus()
}

function cancelEdit(field: PaymentField): void {
  editingFields.value.delete(field)
}

// Reformat in-place as the user types — uppercases, groups into fours — and
// keeps the cursor where they expect it by counting non-space chars before
// the old cursor and re-anchoring there in the new formatted string.
function onIbanInput(event: Event): void {
  const input = event.target as HTMLInputElement
  const oldCursor = input.selectionStart ?? input.value.length
  const oldValue = input.value
  const charsBeforeCursor = oldValue
    .slice(0, oldCursor)
    .replace(/\s/g, '').length

  const formatted = formatIban(oldValue)
  editIban.value = formatted

  let newCursor = 0
  let counted = 0
  while (newCursor < formatted.length && counted < charsBeforeCursor) {
    if (formatted[newCursor] !== ' ') counted++
    newCursor++
  }

  nextTick(() => input.setSelectionRange(newCursor, newCursor))
}

async function persist(
  field: PaymentField,
  payload: { iban?: string; ibanHolderName?: string }
): Promise<void> {
  if (savingFields.value.has(field)) return
  savingFields.value.add(field)
  try {
    await authStore.updateProfile(payload)
    editingFields.value.delete(field)
  } catch {
    // Error handled by mutation/toast
  } finally {
    savingFields.value.delete(field)
  }
}

function saveIban(): Promise<void> {
  if (!canSaveIban.value) return Promise.resolve()
  return persist('iban', { iban: normalizeIban(editIban.value) })
}

function removeIban(): Promise<void> {
  return persist('iban', { iban: '' })
}

function saveHolderName(): Promise<void> {
  if (!canSaveHolderName.value) return Promise.resolve()
  return persist('holderName', { ibanHolderName: editHolderName.value.trim() })
}

function removeHolderName(): Promise<void> {
  return persist('holderName', { ibanHolderName: '' })
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
          :editing="editingFields.has('iban')"
          @edit="openIbanEditor"
        >
          {{ user?.iban ?? 'Not set' }}
          <template #editor>
            <div>
              <form class="flex items-center gap-2" @submit.prevent="saveIban">
                <input
                  ref="ibanInputRef"
                  :value="editIban"
                  type="text"
                  aria-label="IBAN"
                  autocomplete="off"
                  spellcheck="false"
                  placeholder="NL00 BANK 0000 0000 00"
                  :maxlength="42"
                  :disabled="savingFields.has('iban')"
                  :aria-invalid="ibanError !== null"
                  class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 font-mono text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:font-mono placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
                  @input="onIbanInput"
                  @keyup.escape="cancelEdit('iban')"
                />
                <AppButton
                  type="submit"
                  size="sm"
                  :disabled="!canSaveIban"
                  :loading="savingFields.has('iban')"
                >
                  Save
                </AppButton>
                <TextButton
                  variant="secondary"
                  :disabled="savingFields.has('iban')"
                  @click="cancelEdit('iban')"
                >
                  Cancel
                </TextButton>
                <IconButton
                  v-if="user?.iban"
                  variant="danger"
                  label="Remove IBAN"
                  :disabled="savingFields.has('iban')"
                  @click="removeIban"
                >
                  <XCircleIcon class="size-5" />
                </IconButton>
              </form>
              <p
                v-if="ibanError"
                class="mt-1 text-sm text-red-600 dark:text-red-400"
              >
                {{ ibanError }}
              </p>
            </div>
          </template>
        </DefinitionRow>

        <DefinitionRow
          label="Name on bank account"
          value-class="truncate"
          edit-label="Edit name on bank account"
          edit-testid="edit-iban-holder-name-button"
          :editing="editingFields.has('holderName')"
          @edit="openHolderNameEditor"
        >
          <template v-if="user?.ibanHolderName">
            {{ user.ibanHolderName }}
          </template>
          <template v-else>
            <span class="text-gray-500 dark:text-stone-400">
              {{ user?.name ? `${user.name} (your display name)` : 'Not set' }}
            </span>
          </template>
          <template #editor>
            <form
              class="flex items-center gap-2"
              @submit.prevent="saveHolderName"
            >
              <input
                ref="holderNameInputRef"
                v-model="editHolderName"
                type="text"
                aria-label="Name on bank account"
                autocomplete="cc-name"
                placeholder="Exactly as on your bank account"
                :maxlength="70"
                :disabled="savingFields.has('holderName')"
                class="min-w-0 flex-1 rounded-md bg-gray-100 px-3 py-1.5 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
                @keyup.escape="cancelEdit('holderName')"
              />
              <AppButton
                type="submit"
                size="sm"
                :disabled="!canSaveHolderName"
                :loading="savingFields.has('holderName')"
              >
                Save
              </AppButton>
              <TextButton
                variant="secondary"
                :disabled="savingFields.has('holderName')"
                @click="cancelEdit('holderName')"
              >
                Cancel
              </TextButton>
              <IconButton
                v-if="user?.ibanHolderName"
                variant="danger"
                label="Remove name on bank account"
                :disabled="savingFields.has('holderName')"
                @click="removeHolderName"
              >
                <XCircleIcon class="size-5" />
              </IconButton>
            </form>
          </template>
        </DefinitionRow>
      </dl>
    </BaseCard>
  </div>
</template>
