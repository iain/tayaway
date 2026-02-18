<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { UserIcon, PlusIcon } from '@heroicons/vue/24/outline'
import { useMembersStore, useNotificationsStore } from '@/stores'
import AddMemberModal from '@/components/members/AddMemberModal.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import PrimaryButton from '@/components/common/PrimaryButton.vue'

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
    <PageHeader title="Members" data-testid="page-title">
      <PrimaryButton data-testid="add-member-button" @click="openModal">
        <PlusIcon class="size-5" />
        Add Member
      </PrimaryButton>
    </PageHeader>

    <div
      v-if="formError"
      class="mb-4 rounded-md bg-red-900/50 p-4 text-red-400"
    >
      {{ formError }}
    </div>

    <EmptyState
      v-if="members.length === 0"
      :icon="UserIcon"
      heading="No members"
      description="Get started by adding a new member."
    >
      <PrimaryButton @click="openModal">
        <PlusIcon class="size-5" />
        Add Member
      </PrimaryButton>
    </EmptyState>

    <ul
      v-else
      data-testid="members-list"
      class="divide-y divide-gray-200 dark:divide-stone-700"
    >
      <li
        v-for="member in members"
        :key="member.id"
        :data-testid="`member-item-${member.id}`"
        class="mb-4 overflow-hidden rounded-lg bg-white shadow dark:bg-stone-800"
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
                  class="text-sm text-gray-500 dark:text-stone-400"
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
                    'bg-gray-100 text-gray-600 dark:bg-stone-700 dark:text-stone-300':
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
