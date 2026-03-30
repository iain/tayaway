<script setup lang="ts">
import { ref, nextTick, onMounted, onUnmounted } from 'vue'
import { PencilIcon, TrashIcon } from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores'
import type { Passkey } from '@/types'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'

const UNDO_DELAY_MS = 4000

const authStore = useAuthStore()
const notifications = useNotificationsStore()

const passkeys = ref<Passkey[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const registering = ref(false)
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

function defaultName(): string {
  return `Passkey (${new Date().toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })})`
}

async function startRegistration() {
  registering.value = true
  error.value = null
  try {
    const passkey = await authStore.registerPasskey()
    // If FIDO metadata didn't provide a name, use a default
    if (!passkey.name) {
      const name = defaultName()
      try {
        const updated = await authStore.renamePasskey(passkey.id, name)
        passkeys.value.unshift(updated)
      } catch {
        passkeys.value.unshift({ ...passkey, name })
      }
    } else {
      passkeys.value.unshift(passkey)
    }
    notifications.showInfo('Passkey added')
  } catch (e) {
    const name = e instanceof Error ? e.name : ''
    if (name === 'NotAllowedError') return
    if (name === 'InvalidStateError') {
      error.value =
        'This authenticator is already registered. Use a different device or security key.'
      return
    }
    error.value = 'Failed to register passkey. Please try again.'
  } finally {
    registering.value = false
  }
}

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

  // Optimistic update
  passkeys.value = passkeys.value.map((p) => (p.id === id ? { ...p, name } : p))
  editingId.value = null

  try {
    await authStore.renamePasskey(id, name)
  } catch {
    // Revert on failure
    if (original) {
      passkeys.value = passkeys.value.map((p) => (p.id === id ? original : p))
    }
  }
}

function cancelEdit() {
  editingId.value = null
}

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
            <!-- Inline rename form -->
            <form
              v-if="editingId === passkey.id"
              class="flex items-center gap-2"
              @submit.prevent="saveEdit(passkey.id)"
            >
              <input
                :id="`rename-${passkey.id}`"
                v-model="editName"
                type="text"
                maxlength="100"
                aria-label="Passkey name"
                class="block min-w-0 flex-1 rounded-md bg-gray-100 px-2 py-1 text-sm text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500 dark:bg-white/5 dark:text-white dark:outline-white/10"
                @keydown.escape="cancelEdit"
                @blur="saveEdit(passkey.id)"
              />
            </form>

            <!-- Display mode -->
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
        <AppButton
          variant="secondary"
          :loading="registering"
          loading-label="Registering..."
          @click="startRegistration"
        >
          Add passkey
        </AppButton>
      </div>
    </template>
  </div>
</template>
