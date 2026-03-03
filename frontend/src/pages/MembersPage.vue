<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import {
  UserIcon,
  PlusIcon,
  EnvelopeIcon,
  PhoneIcon,
  CakeIcon,
  XMarkIcon,
  IdentificationIcon,
  ArrowPathIcon,
} from '@heroicons/vue/24/outline'
import { useMembersStore, useNotificationsStore } from '@/stores'
import { useAuthStore } from '@/stores/auth'
import { useObjectPoolStore } from '@/stores/objectPool'
import InviteMemberModal from '@/components/members/InviteMemberModal.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import type { PoolMember, PoolWorkspaceInvite } from '@/types/pool'
import { formatBirthday, formatRelativeDate } from '@/utils/date'
import { generateVCard, downloadVCard } from '@/utils/vcard'

const membersStore = useMembersStore()
const { members, pendingInvites } = storeToRefs(membersStore)
const authStore = useAuthStore()
const pool = useObjectPoolStore()

const isModalOpen = ref(false)
const isSubmitting = ref(false)
const remindingInviteId = ref<string | null>(null)
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

function isExpired(invite: PoolWorkspaceInvite): boolean {
  return new Date(invite.expiresAt) < new Date()
}

function canRemind(invite: PoolWorkspaceInvite): boolean {
  const lastSentAt = invite.lastRemindedAt ?? invite.createdAt
  const cooldownUntil = new Date(
    new Date(lastSentAt).getTime() + 24 * 60 * 60 * 1000
  )
  return new Date() >= cooldownUntil
}

function remindAvailableAt(invite: PoolWorkspaceInvite): string {
  const lastSentAt = invite.lastRemindedAt ?? invite.createdAt
  const cooldownUntil = new Date(
    new Date(lastSentAt).getTime() + 24 * 60 * 60 * 1000
  )
  return cooldownUntil.toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  })
}

async function handleRemind(id: string): Promise<void> {
  remindingInviteId.value = id
  try {
    await membersStore.sendReminder(id)
    const notifications = useNotificationsStore()
    notifications.showInfo('Reminder sent')
  } catch (err) {
    const notifications = useNotificationsStore()
    const apiErr = err as { message?: string }
    notifications.showError(apiErr.message || 'Failed to send reminder')
  } finally {
    remindingInviteId.value = null
  }
}

function inviteExpiryText(invite: PoolWorkspaceInvite): string {
  const expiresAt = new Date(invite.expiresAt)
  const now = new Date()
  if (expiresAt < now) {
    return `Expired ${formatRelativeDate(invite.expiresAt)}`
  }
  const diffMs = expiresAt.getTime() - now.getTime()
  const diffMinutes = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMs / 3600000)
  if (diffMinutes < 60) return `Expires in ${diffMinutes}m`
  if (diffHours < 24) return `Expires in ${diffHours}h`
  return `Expires in ${Math.floor(diffHours / 24)}d`
}

function invitedByName(invite: PoolWorkspaceInvite): string | null {
  if (!invite.invitedBy) return null
  const member = pool.findBy('member', 'userId', invite.invitedBy)
  return member ? (member.name ?? member.email) : null
}

function isBirthday(member: PoolMember): boolean {
  if (!member.birthday) return false
  const today = new Date()
  const [, month, day] = member.birthday.split('-')
  return (
    today.getMonth() + 1 === Number(month) && today.getDate() === Number(day)
  )
}

function getInitials(member: PoolMember): string {
  const name = member.name
  if (name) {
    const parts = name.trim().split(/\s+/)
    if (parts.length >= 2) {
      const first = parts[0]?.[0] ?? ''
      const last = parts[parts.length - 1]?.[0] ?? ''
      return (first + last).toUpperCase()
    }
    return (parts[0]?.[0] ?? '').toUpperCase()
  }
  return member.email?.[0]?.toUpperCase() ?? '?'
}

function handleDownloadVCard(member: PoolMember): void {
  const content = generateVCard({
    name: member.name,
    email: member.email,
    phoneNumber: member.phoneNumber,
    birthday: member.birthday,
    locationName: member.locationName,
    latitude: member.latitude,
    longitude: member.longitude,
  })
  const filename = `${member.name || member.email}.vcf`
  downloadVCard(filename, content)
}

onMounted(() => {
  membersStore.fetchInvites()
})
</script>

<template>
  <div>
    <PageHeader title="Members" data-testid="page-title">
      <AppButton data-testid="invite-member-button" @click="openModal">
        <PlusIcon class="size-5" />
        Invite Member
      </AppButton>
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

    <!-- Pending + Expired Invites Section -->
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
                  <div class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1">
                    <span
                      v-if="isExpired(invite)"
                      class="inline-flex items-center rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-800 dark:bg-red-900/30 dark:text-red-400"
                    >
                      Expired
                    </span>
                    <span
                      v-else
                      class="inline-flex items-center rounded-full bg-yellow-100 px-2 py-0.5 text-xs font-medium text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400"
                    >
                      Pending
                    </span>
                    <span class="text-xs text-gray-400 dark:text-stone-500">
                      Sent {{ formatRelativeDate(invite.createdAt) }}
                      <template v-if="invitedByName(invite)">
                        by {{ invitedByName(invite) }}
                      </template>
                      · {{ inviteExpiryText(invite) }}
                    </span>
                  </div>
                </div>
              </div>
              <div class="flex items-center gap-1">
                <IconButton
                  :label="
                    isExpired(invite) ? 'Resend invitation' : 'Send reminder'
                  "
                  :disabled="
                    !canRemind(invite) || remindingInviteId === invite.id
                  "
                  :title="
                    !canRemind(invite)
                      ? `Available at ${remindAvailableAt(invite)}`
                      : isExpired(invite)
                        ? 'Resend invitation'
                        : 'Send reminder'
                  "
                  data-testid="remind-invite-button"
                  @click="handleRemind(invite.id)"
                >
                  <ArrowPathIcon
                    class="size-5"
                    :class="{ 'animate-spin': remindingInviteId === invite.id }"
                  />
                </IconButton>
                <IconButton
                  label="Cancel invitation"
                  data-testid="cancel-invite-button"
                  @click="handleCancelInvite(invite.id)"
                >
                  <XMarkIcon class="size-5" />
                </IconButton>
              </div>
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
      <AppButton @click="openModal">
        <PlusIcon class="size-5" />
        Invite Member
      </AppButton>
    </EmptyState>

    <div
      v-else
      data-testid="members-list"
      class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
    >
      <BaseCard
        v-for="member in members"
        :key="member.id"
        :data-testid="`member-item-${member.id}`"
        class="row-span-2 grid grid-rows-subgrid"
        :class="[
          currentMember?.id === member.id &&
            !isBirthday(member) &&
            'ring-2 ring-rose-300 dark:ring-rose-700',
          isBirthday(member) && 'birthday-card',
        ]"
      >
        <!-- Top section: avatar + identity -->
        <div class="relative flex items-start gap-4 p-5">
          <div
            v-if="isBirthday(member)"
            class="pointer-events-none absolute inset-x-0 top-0 flex justify-between px-3 pt-1 text-xl"
          >
            <span class="birthday-float" style="animation-delay: 0s">🎉</span>
            <span class="birthday-float" style="animation-delay: 0.4s">🎈</span>
            <span class="birthday-float" style="animation-delay: 0.8s">🎊</span>
            <span class="birthday-float" style="animation-delay: 0.2s">🥳</span>
            <span class="birthday-float" style="animation-delay: 0.6s">🎂</span>
          </div>
          <div
            class="flex size-12 shrink-0 items-center justify-center rounded-full text-lg font-semibold"
            :class="
              isBirthday(member)
                ? 'animate-bounce bg-amber-300 text-amber-900 ring-4 ring-amber-400/50 dark:bg-amber-500 dark:text-amber-950 dark:ring-amber-500/50'
                : 'bg-rose-100 text-rose-600 dark:bg-rose-900/30 dark:text-rose-400'
            "
          >
            {{ isBirthday(member) ? '🎂' : getInitials(member) }}
          </div>
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <h2
                data-testid="member-name"
                class="truncate text-lg font-semibold text-gray-900 dark:text-white"
              >
                {{ member.name || 'No name' }}
              </h2>
              <select
                v-if="canChangeRole(member)"
                data-testid="member-role-select"
                :value="member.role"
                class="inline-flex shrink-0 cursor-pointer items-center rounded-full border-0 px-2 py-0.5 text-xs font-medium focus:ring-2 focus:ring-indigo-500 focus:outline-none focus:ring-inset"
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
                class="inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-xs font-medium"
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
            <p
              v-if="isBirthday(member)"
              class="birthday-shimmer text-sm font-bold"
            >
              🎉 Happy Birthday! 🎉
            </p>
            <p
              data-testid="member-email"
              class="truncate text-sm text-gray-500 dark:text-stone-400"
            >
              {{ member.email }}
            </p>
            <p
              v-if="member.birthday && !isBirthday(member)"
              class="flex items-center gap-1 text-sm text-gray-500 dark:text-stone-400"
            >
              <CakeIcon class="size-3.5" />
              {{ formatBirthday(member.birthday) }}
            </p>
          </div>
        </div>

        <!-- Bottom section: action buttons -->
        <div
          class="flex items-center gap-1 border-t border-gray-200 px-5 py-3 dark:border-stone-700"
        >
          <a
            :href="`mailto:${member.email}`"
            class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 dark:text-stone-300 dark:hover:bg-stone-700"
          >
            <EnvelopeIcon class="size-4" />
            Email
          </a>
          <a
            v-if="member.phoneNumber"
            :href="`tel:${member.phoneNumber}`"
            class="inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 dark:text-stone-300 dark:hover:bg-stone-700"
          >
            <PhoneIcon class="size-4" />
            Call
          </a>
          <button
            data-testid="download-vcard-button"
            class="ml-auto inline-flex cursor-pointer items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 dark:text-stone-300 dark:hover:bg-stone-700"
            title="Download contact card"
            @click="handleDownloadVCard(member)"
          >
            <IdentificationIcon class="size-4" />
            vCard
          </button>
        </div>
      </BaseCard>
    </div>

    <InviteMemberModal
      :open="isModalOpen"
      :loading="isSubmitting"
      @close="closeModal"
      @save="handleSave"
    />
  </div>
</template>

<style scoped>
.birthday-card {
  background: linear-gradient(
    135deg,
    #fef3c7 0%,
    #fce7f3 25%,
    #ede9fe 50%,
    #dbeafe 75%,
    #fef3c7 100%
  );
  background-size: 300% 300%;
  animation: birthday-gradient 4s ease infinite;
  box-shadow:
    0 0 15px rgba(251, 191, 36, 0.4),
    0 0 30px rgba(244, 114, 182, 0.2);
}

:where(.dark) .birthday-card {
  background: linear-gradient(
    135deg,
    #78350f 0%,
    #831843 25%,
    #4c1d95 50%,
    #1e3a5f 75%,
    #78350f 100%
  );
  background-size: 300% 300%;
  animation: birthday-gradient 4s ease infinite;
  box-shadow:
    0 0 15px rgba(251, 191, 36, 0.3),
    0 0 30px rgba(244, 114, 182, 0.15);
}

@keyframes birthday-gradient {
  0%,
  100% {
    background-position: 0% 50%;
  }
  50% {
    background-position: 100% 50%;
  }
}

.birthday-float {
  animation: birthday-bob 2s ease-in-out infinite;
}

@keyframes birthday-bob {
  0%,
  100% {
    transform: translateY(0);
  }
  50% {
    transform: translateY(-6px);
  }
}

.birthday-shimmer {
  background: linear-gradient(
    90deg,
    #f59e0b,
    #ec4899,
    #8b5cf6,
    #f59e0b,
    #ec4899
  );
  background-size: 200% auto;
  background-clip: text;
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  animation: birthday-shimmer-move 2s linear infinite;
}

@keyframes birthday-shimmer-move {
  to {
    background-position: 200% center;
  }
}
</style>
