<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import {
  UserIcon,
  PlusIcon,
  EnvelopeIcon,
  XMarkIcon,
} from '@heroicons/vue/24/outline'
import { useMembersStore, useNotificationsStore } from '@/stores'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores/objectPool'
import InviteMemberModal from '@/components/members/InviteMemberModal.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import PrimaryButton from '@/components/common/PrimaryButton.vue'
import type { PoolMember } from '@/types/pool'

const membersStore = useMembersStore()
const { members, pendingInvites } = storeToRefs(membersStore)
const authStore = useAuthStore()
const pool = useObjectPoolStore()

const isModalOpen = ref(false)
const isSubmitting = ref(false)
const formError = ref<string | null>(null)
const roleError = ref<string | null>(null)

const currentMember = computed((): PoolMember | null => {
  const userId = authStore.currentUserId
  if (!userId) return null
  return pool.findBy('member', 'userId', userId) ?? null
})

function canChangeRole(member: PoolMember): boolean {
  const me = currentMember.value
  if (!me || me.id === member.id) return false
  if (me.role === 'owner') return true
  if (me.role === 'admin') return member.role !== 'owner'
  return false
}

function availableRolesFor(): string[] {
  const me = currentMember.value
  if (!me) return []
  if (me.role === 'owner') return ['owner', 'admin', 'member']
  if (me.role === 'admin') return ['admin', 'member']
  return []
}

async function handleRoleChange(
  member: PoolMember,
  newRole: string
): Promise<void> {
  if (newRole === member.role) return
  roleError.value = null
  try {
    await membersStore.updateMemberRole(member.id, newRole)
  } catch {
    roleError.value = 'Failed to update role'
  }
}

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
    await membersStore.createInvite(email, name || undefined)
    isModalOpen.value = false
    const notifications = useNotificationsStore()
    notifications.showInfo('Invitation sent')
  } catch {
    formError.value =
      'Failed to send invitation. The email may already be a member.'
  } finally {
    isSubmitting.value = false
  }
}

async function handleCancelInvite(id: string): Promise<void> {
  try {
    await membersStore.cancelInvite(id)
  } catch {
    const notifications = useNotificationsStore()
    notifications.showError('Failed to cancel invitation')
  }
}

onMounted(() => {
  membersStore.fetchInvites()
})
</script>

<template>
  <div>
    <PageHeader title="Members" data-testid="page-title">
      <PrimaryButton data-testid="invite-member-button" @click="openModal">
        <PlusIcon class="size-5" />
        Invite Member
      </PrimaryButton>
    </PageHeader>

    <div
      v-if="formError"
      class="mb-4 rounded-md bg-red-900/50 p-4 text-red-400"
    >
      {{ formError }}
    </div>

    <div
      v-if="roleError"
      class="mb-4 rounded-md bg-red-900/50 p-4 text-red-400"
    >
      {{ roleError }}
    </div>

    <!-- Pending Invites Section -->
    <div
      v-if="pendingInvites.length > 0"
      class="mb-6"
      data-testid="pending-invites-section"
    >
      <h2
        class="mb-3 text-sm font-semibold tracking-wide text-gray-500 uppercase dark:text-stone-400"
      >
        Pending Invitations
      </h2>
      <ul class="divide-y divide-gray-200 dark:divide-stone-700">
        <li
          v-for="invite in pendingInvites"
          :key="invite.id"
          class="mb-2 overflow-hidden rounded-lg bg-white shadow dark:bg-stone-800"
        >
          <div class="px-4 py-3 sm:px-6">
            <div class="flex items-center justify-between">
              <div class="flex items-center">
                <EnvelopeIcon class="mr-3 size-8 text-gray-400" />
                <div>
                  <p
                    class="text-sm font-medium text-gray-900 dark:text-white"
                    data-testid="invite-email"
                  >
                    {{
                      invite.name
                        ? `${invite.name} (${invite.email})`
                        : invite.email
                    }}
                  </p>
                  <span
                    class="inline-flex items-center rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400"
                  >
                    Pending
                  </span>
                </div>
              </div>
              <button
                data-testid="cancel-invite-button"
                class="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-stone-700 dark:hover:text-stone-300"
                title="Cancel invitation"
                @click="handleCancelInvite(invite.id)"
              >
                <XMarkIcon class="size-5" />
              </button>
            </div>
          </div>
        </li>
      </ul>
    </div>

    <EmptyState
      v-if="members.length === 0"
      :icon="UserIcon"
      heading="No members"
      description="Get started by inviting a new member."
    >
      <PrimaryButton @click="openModal">
        <PlusIcon class="size-5" />
        Invite Member
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
                <select
                  v-if="canChangeRole(member)"
                  data-testid="member-role-select"
                  :value="member.role"
                  class="inline-flex cursor-pointer items-center rounded-full border-0 px-2 py-0.5 text-xs font-medium focus:ring-2 focus:ring-indigo-500 focus:outline-none focus:ring-inset"
                  :class="{
                    'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-400':
                      member.role === 'owner',
                    'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400':
                      member.role === 'admin',
                    'bg-gray-100 text-gray-600 dark:bg-stone-700 dark:text-stone-300':
                      member.role === 'member',
                  }"
                  @change="
                    handleRoleChange(
                      member,
                      ($event.target as HTMLSelectElement).value
                    )
                  "
                >
                  <option
                    v-for="role in availableRolesFor()"
                    :key="role"
                    :value="role"
                  >
                    {{ role }}
                  </option>
                </select>
                <span
                  v-else-if="member.role"
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

    <InviteMemberModal
      :open="isModalOpen"
      :loading="isSubmitting"
      @close="closeModal"
      @save="handleSave"
    />
  </div>
</template>
