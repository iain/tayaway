<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useNotificationsStore } from '@/stores'
import type { Passkey } from '@/types'
import AppButton from '@/components/common/AppButton.vue'
import TextButton from '@/components/common/TextButton.vue'

const authStore = useAuthStore()
const notifications = useNotificationsStore()

const passkeys = ref<Passkey[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const registering = ref(false)
const nameInput = ref('')
const showNamePrompt = ref(false)
const pendingPasskey = ref<Passkey | null>(null)

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

async function startRegistration() {
  registering.value = true
  error.value = null
  try {
    const passkey = await authStore.registerPasskey()
    // If the device had no FIDO metadata name, prompt user for a name
    if (!passkey.name) {
      pendingPasskey.value = passkey
      showNamePrompt.value = true
      nameInput.value = ''
    } else {
      passkeys.value.unshift(passkey)
      notifications.showInfo('Passkey added')
    }
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

async function savePasskeyName() {
  if (!pendingPasskey.value) return
  const name = nameInput.value.trim()

  if (name) {
    try {
      const updated = await authStore.renamePasskey(
        pendingPasskey.value.id,
        name
      )
      passkeys.value.unshift(updated)
    } catch {
      // If rename fails, still show the passkey with no name
      passkeys.value.unshift(pendingPasskey.value)
    }
  } else {
    passkeys.value.unshift(pendingPasskey.value)
  }

  showNamePrompt.value = false
  pendingPasskey.value = null
  notifications.showInfo('Passkey added')
}

async function deletePasskey(id: string) {
  const passkey = passkeys.value.find((p) => p.id === id)
  if (!passkey) return

  passkeys.value = passkeys.value.filter((p) => p.id !== id)

  try {
    await authStore.deletePasskey(id)
    notifications.showInfo('Passkey removed')
  } catch {
    // Restore on failure
    passkeys.value.push(passkey)
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
      <!-- Name prompt for newly registered passkey -->
      <div
        v-if="showNamePrompt"
        class="mb-4 rounded-md border border-stone-700 bg-stone-800 p-4"
      >
        <p class="mb-2 text-sm text-white">
          Give this passkey a name so you can identify it later:
        </p>
        <form class="flex gap-2" @submit.prevent="savePasskeyName">
          <input
            v-model="nameInput"
            type="text"
            placeholder='e.g. "MacBook", "iPhone"'
            maxlength="100"
            class="block min-w-0 flex-1 rounded-md bg-white/5 px-3 py-1.5 text-sm text-white outline-1 -outline-offset-1 outline-white/10 placeholder:text-stone-500 focus:outline-2 focus:-outline-offset-2 focus:outline-rose-500"
          />
          <AppButton type="submit" variant="amber"> Save </AppButton>
        </form>
      </div>

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
            <p
              class="truncate text-sm font-medium text-gray-900 dark:text-white"
            >
              {{ passkey.name || 'Unnamed passkey' }}
            </p>
            <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
              Added {{ formatDate(passkey.createdAt) }}
            </p>
          </div>
          <TextButton
            variant="danger"
            class="ml-4 shrink-0"
            @click="deletePasskey(passkey.id)"
          >
            Remove
          </TextButton>
        </li>
      </ul>

      <p
        v-else-if="!showNamePrompt"
        class="py-4 text-sm text-gray-500 dark:text-stone-400"
      >
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
