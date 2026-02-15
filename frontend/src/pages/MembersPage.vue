<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { UserIcon, PlusIcon } from '@heroicons/vue/24/outline'
import { useMembersStore, useNotificationsStore } from '@/stores'
import AddMemberModal from '@/components/members/AddMemberModal.vue'

const membersStore = useMembersStore()
const { members } = storeToRefs(membersStore)

const isModalOpen = ref(false)
const isSubmitting = ref(false)
const formError = ref<string | null>(null)

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
    const { queued } = await membersStore.createMember({
      name: name || undefined,
      email: email,
    })
    isModalOpen.value = false
    if (queued) {
      const notifications = useNotificationsStore()
      notifications.showInfo('Member will be added when back online')
    }
  } catch {
    formError.value = 'Failed to add member. The email may already exist.'
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
        Members
      </h1>
      <button
        type="button"
        data-testid="add-member-button"
        class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
        @click="openModal"
      >
        <PlusIcon class="size-5" />
        Add Member
      </button>
    </header>

    <div
      v-if="formError"
      class="mb-4 rounded-md bg-red-900/50 p-4 text-red-400"
    >
      {{ formError }}
    </div>

    <div v-if="members.length === 0" class="py-12 text-center">
      <UserIcon class="mx-auto size-12 text-gray-400" />
      <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
        No members
      </h3>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        Get started by adding a new member.
      </p>
      <div class="mt-6">
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-md bg-rose-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-rose-500"
          @click="openModal"
        >
          <PlusIcon class="size-5" />
          Add Member
        </button>
      </div>
    </div>

    <ul
      v-else
      data-testid="members-list"
      class="divide-y divide-gray-200 dark:divide-gray-700"
    >
      <li
        v-for="member in members"
        :key="member.id"
        :data-testid="`member-item-${member.id}`"
        class="mb-4 overflow-hidden rounded-lg bg-white shadow dark:bg-gray-800"
      >
        <div class="px-4 py-5 sm:px-6">
          <div class="flex items-center">
            <UserIcon class="mr-4 size-10 text-gray-400" />
            <div class="min-w-0 flex-1">
              <h2
                data-testid="member-name"
                class="truncate text-lg font-semibold text-gray-900 dark:text-white"
              >
                {{ member.name || 'No name' }}
              </h2>
              <div class="flex items-center gap-2">
                <p
                  data-testid="member-email"
                  class="text-sm text-gray-500 dark:text-gray-400"
                >
                  {{ member.email }}
                </p>
                <span
                  v-if="member.role"
                  data-testid="member-role"
                  class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
                  :class="{
                    'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-400':
                      member.role === 'owner',
                    'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400':
                      member.role === 'admin',
                    'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-300':
                      member.role === 'member',
                  }"
                >
                  {{ member.role }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </li>
    </ul>

    <AddMemberModal
      :open="isModalOpen"
      :loading="isSubmitting"
      @close="closeModal"
      @save="handleSave"
    />
  </div>
</template>
