<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import { UserIcon, PlusIcon } from '@heroicons/vue/24/outline'
import { useUsersStore } from '@/stores'
import AddUserModal from '@/components/users/AddUserModal.vue'

const usersStore = useUsersStore()
const { users, loading, error } = storeToRefs(usersStore)

const isModalOpen = ref(false)
const isSubmitting = ref(false)
const formError = ref<string | null>(null)

onMounted(() => {
  usersStore.fetchUsers()
})

function openModal(): void {
  formError.value = null
  isModalOpen.value = true
}

function closeModal(): void {
  isModalOpen.value = false
}

async function handleSave(name: string, email: string): Promise<void> {
  formError.value = null
  isSubmitting.value = true

  try {
    await usersStore.createUser({
      name: name || undefined,
      email: email
    })
    isModalOpen.value = false
  } catch {
    formError.value = 'Failed to create user. The email may already exist.'
  } finally {
    isSubmitting.value = false
  }
}
</script>

<template>
  <div>
    <header class="mb-6 flex items-center justify-between">
      <h1
        data-testid="page-title"
        class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
      >
        Users
      </h1>
      <button
        type="button"
        data-testid="add-user-button"
        class="inline-flex items-center gap-2 rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
        @click="openModal"
      >
        <PlusIcon class="size-5" />
        Add User
      </button>
    </header>

    <div
      v-if="formError"
      class="mb-4 rounded-md bg-red-900/50 p-4 text-red-400"
    >
      {{ formError }}
    </div>

    <div
      v-if="loading && users.length === 0"
      class="text-gray-500 dark:text-gray-400"
    >
      Loading users...
    </div>

    <div
      v-else-if="error && users.length === 0"
      class="text-red-600 dark:text-red-400"
    >
      {{ error }}
    </div>

    <div
      v-else-if="users.length === 0"
      class="text-center py-12"
    >
      <UserIcon class="mx-auto size-12 text-gray-400" />
      <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
        No users
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        Get started by adding a new user.
      </p>
      <div class="mt-6">
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500"
          @click="openModal"
        >
          <PlusIcon class="size-5" />
          Add User
        </button>
      </div>
    </div>

    <ul
      v-else
      data-testid="users-list"
      class="divide-y divide-gray-200 dark:divide-gray-700"
    >
      <li
        v-for="user in users"
        :key="user.id"
        :data-testid="`user-item-${user.id}`"
        class="bg-white dark:bg-gray-800 shadow rounded-lg mb-4 overflow-hidden"
      >
        <div class="px-4 py-5 sm:px-6">
          <div class="flex items-center">
            <UserIcon class="size-10 text-gray-400 mr-4" />
            <div class="min-w-0 flex-1">
              <h2
                data-testid="user-name"
                class="text-lg font-semibold text-gray-900 dark:text-white truncate"
              >
                {{ user.name || 'No name' }}
              </h2>
              <p
                data-testid="user-email"
                class="text-sm text-gray-500 dark:text-gray-400"
              >
                {{ user.email }}
              </p>
            </div>
          </div>
        </div>
      </li>
    </ul>

    <AddUserModal
      :open="isModalOpen"
      :loading="isSubmitting"
      @close="closeModal"
      @save="handleSave"
    />
  </div>
</template>
