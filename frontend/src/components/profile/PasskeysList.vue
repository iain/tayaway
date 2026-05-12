<script setup lang="ts">
import { ref, nextTick, onMounted, onUnmounted } from 'vue'
import { PencilIcon, TrashIcon, ArrowPathIcon } from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores'
import type { Passkey } from '@/types'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'

const UNDO_DELAY_MS = 4000

const authStore = useAuthStore()
const notifications = useNotificationsStore()

const passkeys = ref<Passkey[]>([])
const loading = ref(true)
const error = ref<string | null>(null)

// --- Registration modal state ---
const registerOpen = ref(false)
const registerStep = ref<'ready' | 'ceremony' | 'name' | 'error'>('ready')
const registerError = ref<string | null>(null)
const registerSaving = ref(false)
const pendingPasskey = ref<Passkey | null>(null)
const passkeyName = ref('')

// --- Inline rename state ---
const editingId = ref<string | null>(null)
const editName = ref('')

async function fetchPasskeys() {
  loading.value = true
  error.value = null
  try {
    passkeys.value = await authStore.listPasskeys()
  } catch {
    error.value = 'Could not load passkeys. Please try again.'
  } finally {
    loading.value = false
  }
}

function openRegisterModal() {
  registerOpen.value = true
  registerStep.value = 'ready'
  registerError.value = null
  pendingPasskey.value = null
  passkeyName.value = ''
}

async function startCeremony() {
  registerStep.value = 'ceremony'
  registerError.value = null

  try {
    const passkey = await authStore.registerPasskey()
    pendingPasskey.value = passkey
    passkeyName.value = passkey.name || ''
    registerStep.value = 'name'
    nextTick(() => document.getElementById('passkey-name')?.focus())
  } catch (e) {
    const name = e instanceof Error ? e.name : ''
    if (name === 'NotAllowedError') {
      registerOpen.value = false
      return
    }
    if (name === 'InvalidStateError') {
      registerError.value =
        'This authenticator is already registered. Use a different device or security key.'
      registerStep.value = 'error'
      return
    }
    registerError.value = 'Failed to register passkey. Please try again.'
    registerStep.value = 'error'
  }
}

async function savePasskeyName() {
  if (!pendingPasskey.value) return
  const name = passkeyName.value.trim()
  if (!name) return

  registerSaving.value = true
  try {
    const updated = await authStore.renamePasskey(pendingPasskey.value.id, name)
    passkeys.value.unshift(updated)
    pendingPasskey.value = null // Clear before closing to prevent double-add in closeRegisterModal
    registerOpen.value = false
    notifications.showInfo('Passkey added')
  } catch {
    registerError.value = 'Failed to save name. Please try again.'
  } finally {
    registerSaving.value = false
  }
}

async function closeRegisterModal() {
  // Canceling deletes the passkey — name is mandatory
  if (pendingPasskey.value) {
    try {
      await authStore.deletePasskey(pendingPasskey.value.id)
    } catch {
      // Best-effort cleanup
    }
    pendingPasskey.value = null
  }
  registerOpen.value = false
}

// --- Inline rename ---
function startEditing(passkey: Passkey) {
  editingId.value = passkey.id
  editName.value = passkey.name || ''
  nextTick(() => {
    const input = document.getElementById(`rename-${passkey.id}`)
    input?.focus()
  })
}

async function saveEdit(id: string) {
  const name = editName.value.trim()
  if (!name) {
    editingId.value = null
    return
  }

  const original = passkeys.value.find((p) => p.id === id)
  if (original && original.name === name) {
    editingId.value = null
    return
  }

  passkeys.value = passkeys.value.map((p) => (p.id === id ? { ...p, name } : p))
  editingId.value = null

  try {
    await authStore.renamePasskey(id, name)
  } catch {
    if (original) {
      passkeys.value = passkeys.value.map((p) => (p.id === id ? original : p))
    }
  }
}

function cancelEdit() {
  editingId.value = null
}

// --- Delete with undo ---
const pendingDeletes = ref<
  Map<string, { passkey: Passkey; timer: ReturnType<typeof setTimeout> }>
>(new Map())

function deletePasskey(id: string) {
  const passkey = passkeys.value.find((p) => p.id === id)
  if (!passkey) return

  passkeys.value = passkeys.value.filter((p) => p.id !== id)
  editingId.value = null

  const timer = setTimeout(() => {
    executeDelete(id)
  }, UNDO_DELAY_MS)

  pendingDeletes.value.set(id, { passkey, timer })

  notifications.showInfo('Passkey removed', {
    actionLabel: 'Undo',
    duration: UNDO_DELAY_MS,
    action: () => undoDelete(id),
  })
}

function undoDelete(id: string) {
  const pending = pendingDeletes.value.get(id)
  if (!pending) return

  clearTimeout(pending.timer)
  pendingDeletes.value.delete(id)

  passkeys.value.push(pending.passkey)
  passkeys.value.sort(
    (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
  )
}

async function executeDelete(id: string) {
  pendingDeletes.value.delete(id)
  try {
    await authStore.deletePasskey(id)
  } catch {
    // Error notification handled by api client
  }
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

onMounted(fetchPasskeys)

onUnmounted(() => {
  for (const [id, { timer }] of pendingDeletes.value) {
    clearTimeout(timer)
    executeDelete(id)
  }
})
</script>

<template>
  <div>
    <div
      v-if="loading"
      role="status"
      aria-live="polite"
      class="py-4 text-sm text-gray-500 dark:text-stone-400"
    >
      Loading passkeys...
    </div>

    <div
      v-else-if="error"
      role="alert"
      class="py-4 text-sm text-red-600 dark:text-red-400"
    >
      {{ error }}
    </div>

    <template v-else>
      <ul
        v-if="passkeys.length > 0"
        class="divide-y divide-gray-200 dark:divide-stone-700"
      >
        <li
          v-for="passkey in passkeys"
          :key="passkey.id"
          class="flex items-center justify-between py-4"
        >
          <div class="min-w-0 flex-1">
            <form
              v-if="editingId === passkey.id"
              class="flex items-center gap-2"
              @submit.prevent="saveEdit(passkey.id)"
            >
              <label :for="`rename-${passkey.id}`" class="sr-only">
                Rename passkey
              </label>
              <input
                :id="`rename-${passkey.id}`"
                v-model="editName"
                type="text"
                maxlength="100"
                placeholder="Enter a name"
                class="block min-w-0 flex-1 rounded-md bg-gray-100 px-2 py-1 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-focus dark:bg-white/5 dark:text-white dark:outline-white/10 dark:placeholder:text-stone-500"
                @keydown.escape="cancelEdit"
              />
              <AppButton type="submit" size="sm"> Save </AppButton>
              <AppButton size="sm" variant="secondary" @click="cancelEdit">
                Cancel
              </AppButton>
            </form>

            <template v-else>
              <p
                class="truncate text-sm font-medium text-gray-900 dark:text-white"
              >
                {{ passkey.name || 'Unnamed passkey' }}
              </p>
              <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
                Added {{ formatDate(passkey.createdAt) }}
              </p>
            </template>
          </div>
          <div
            v-if="editingId !== passkey.id"
            class="ml-4 flex shrink-0 items-center gap-1"
          >
            <IconButton label="Rename passkey" @click="startEditing(passkey)">
              <PencilIcon class="size-4" />
            </IconButton>
            <IconButton
              variant="danger"
              label="Delete passkey"
              @click="deletePasskey(passkey.id)"
            >
              <TrashIcon class="size-4" />
            </IconButton>
          </div>
        </li>
      </ul>

      <p v-else class="py-4 text-sm text-gray-500 dark:text-stone-400">
        No passkeys registered. Add a passkey for faster, more secure sign-in.
      </p>

      <div class="mt-4">
        <AppButton variant="secondary" @click="openRegisterModal">
          Add passkey
        </AppButton>
      </div>
    </template>

    <!-- Registration modal -->
    <BaseModal
      :open="registerOpen"
      title="Add Passkey"
      :prevent-close="registerStep === 'ceremony'"
      @close="closeRegisterModal"
    >
      <!-- Step 1: Ready to start -->
      <div v-if="registerStep === 'ready'" class="space-y-4">
        <p class="text-sm text-gray-500 dark:text-stone-400">
          Your browser will ask you to verify your identity. This usually means
          using Touch ID, Face ID, Windows Hello, or a security key.
        </p>
        <div class="flex justify-end gap-x-6">
          <button
            type="button"
            class="min-h-[44px] px-3 py-2 text-sm/6 font-semibold text-gray-900 sm:min-h-0 dark:text-white"
            @click="registerOpen = false"
          >
            Cancel
          </button>
          <AppButton autofocus @click="startCeremony"> Continue </AppButton>
        </div>
      </div>

      <!-- Step 2: Ceremony in progress -->
      <div
        v-else-if="registerStep === 'ceremony'"
        class="flex flex-col items-center gap-4 py-6"
      >
        <ArrowPathIcon
          class="size-8 animate-spin text-gray-400 dark:text-stone-500"
        />
        <p class="text-sm text-gray-500 dark:text-stone-400">
          Follow your browser's prompt to create a passkey...
        </p>
      </div>

      <!-- Step 3: Name the passkey -->
      <form
        v-else-if="registerStep === 'name'"
        class="space-y-4"
        @submit.prevent="savePasskeyName"
      >
        <p class="text-sm text-gray-500 dark:text-stone-400">
          Give this passkey a name so you can identify it later.
        </p>

        <FormInput
          id="passkey-name"
          v-model="passkeyName"
          label="Passkey name"
          placeholder='e.g. "MacBook", "iPhone"'
          :maxlength="100"
          required
          :disabled="registerSaving"
        />

        <p v-if="registerError" class="text-sm text-red-600 dark:text-red-400">
          {{ registerError }}
        </p>

        <FormActions
          submit-label="Save"
          :loading="registerSaving"
          :disabled="!passkeyName.trim()"
          @cancel="closeRegisterModal"
        />
      </form>

      <!-- Error during ceremony -->
      <div v-else-if="registerStep === 'error'" class="space-y-4">
        <p class="text-sm text-red-600 dark:text-red-400">
          {{ registerError }}
        </p>
        <div class="flex justify-end">
          <AppButton variant="secondary" @click="registerOpen = false">
            Close
          </AppButton>
        </div>
      </div>
    </BaseModal>
  </div>
</template>
