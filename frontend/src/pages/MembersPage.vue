<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { storeToRefs } from 'pinia'
import {
  UserIcon,
  UsersIcon,
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
import { useWorkspaceStore } from '@/stores/workspace'
import InviteMemberModal from '@/components/members/InviteMemberModal.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import AppButton from '@/components/common/AppButton.vue'
import IconButton from '@/components/common/IconButton.vue'
import AppBadge from '@/components/common/AppBadge.vue'
import AppAvatar from '@/components/common/AppAvatar.vue'
import TimeAnchor from '@/components/common/TimeAnchor.vue'
import AlertBox from '@/components/common/AlertBox.vue'
import type { PoolMember, PoolWorkspaceInvite } from '@/types/pool'
import { can } from '@/composables/usePermission'
import { formatBirthday } from '@/utils/date'
import { generateVCard, downloadVCard } from '@/utils/vcard'
import { getInitials } from '@/utils/member'

const membersStore = useMembersStore()
const { members, pendingInvites } = storeToRefs(membersStore)
const authStore = useAuthStore()
const pool = useObjectPoolStore()
const workspaceStore = useWorkspaceStore()

const canInvite = computed(() =>
  can(workspaceStore.currentWorkspace?.permissions, 'invite')
)

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
  return can(member.permissions, 'change_role')
}

function availableRolesFor(member: PoolMember): string[] {
  const perm = member.permissions?.availableRoles
  if (Array.isArray(perm)) return perm
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
    notifications.showInfo('Invitation email sent')
  } catch {
    formError.value =
      'Could not send invitation. This email may already be a member or have a pending invite.'
  } finally {
    isSubmitting.value = false
  }
}

const cancellingInviteId = ref<string | null>(null)

async function handleCancelInvite(id: string): Promise<void> {
  if (cancellingInviteId.value === id) return
  cancellingInviteId.value = id
  try {
    await membersStore.cancelInvite(id)
  } catch {
    const notifications = useNotificationsStore()
    notifications.showError('Could not cancel invitation. Please try again.')
  } finally {
    cancellingInviteId.value = null
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
    notifications.showInfo('Reminder email sent')
  } catch (err) {
    const notifications = useNotificationsStore()
    const apiErr = err as { message?: string }
    notifications.showError(apiErr.message || 'Failed to send reminder')
  } finally {
    remindingInviteId.value = null
  }
}

function inviteExpiryVerb(invite: PoolWorkspaceInvite): 'Expired' | 'Expires' {
  return new Date(invite.expiresAt) < new Date() ? 'Expired' : 'Expires'
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
    <PageHeader title="Members" :icon="UsersIcon" data-testid="page-title">
      <AppButton
        v-if="canInvite"
        data-testid="invite-member-button"
        @click="openModal"
      >
        <PlusIcon class="size-5" />
        Invite Member
      </AppButton>
    </PageHeader>

    <AlertBox v-if="formError" class="mb-4">
      {{ formError }}
    </AlertBox>

    <AlertBox v-if="roleError" class="mb-4">
      {{ roleError }}
    </AlertBox>

    <!-- Pending + Expired Invites Section -->
    <div
      v-if="pendingInvites.length > 0"
      class="mb-6"
      data-testid="pending-invites-section"
    >
      <h2
        class="text-ink-muted mb-3 text-sm font-semibold tracking-wide uppercase"
      >
        Pending Invitations
      </h2>
      <ul class="divide-line divide-y">
        <BaseCard
          v-for="invite in pendingInvites"
          :key="invite.id"
          as="li"
          class="mb-2 overflow-hidden"
        >
          <div class="px-4 py-3 sm:px-6">
            <div class="flex items-center justify-between">
              <div class="flex min-w-0 items-center">
                <EnvelopeIcon class="mr-3 size-8 shrink-0 text-gray-400" />
                <div class="min-w-0 flex-1">
                  <p
                    class="text-ink truncate text-sm font-medium"
                    data-testid="invite-email"
                    :title="
                      invite.name
                        ? `${invite.name} (${invite.email})`
                        : invite.email
                    "
                  >
                    {{
                      invite.name
                        ? `${invite.name} (${invite.email})`
                        : invite.email
                    }}
                  </p>
                  <div class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1">
                    <AppBadge v-if="isExpired(invite)" variant="danger">
                      Expired
                    </AppBadge>
                    <AppBadge v-else variant="warning"> Pending </AppBadge>
                    <span class="text-ink-muted text-xs">
                      <TimeAnchor :at="invite.createdAt">Sent</TimeAnchor>
                      <template v-if="invitedByName(invite)">
                        by {{ invitedByName(invite) }}
                      </template>
                      ·
                      <TimeAnchor :at="invite.expiresAt">
                        {{ inviteExpiryVerb(invite) }}
                      </TimeAnchor>
                    </span>
                  </div>
                </div>
              </div>
              <div
                v-if="can(invite.permissions, 'remind')"
                class="flex items-center gap-1"
              >
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
                  :disabled="cancellingInviteId === invite.id"
                  data-testid="cancel-invite-button"
                  @click="handleCancelInvite(invite.id)"
                >
                  <XMarkIcon class="size-5" />
                </IconButton>
              </div>
            </div>
          </div>
        </BaseCard>
      </ul>
    </div>

    <EmptyState
      v-if="members.length === 0"
      :icon="UserIcon"
      heading="No members yet"
      description="Invite your friends so they can vote on dates, RSVP, and split costs."
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
          <AppAvatar
            v-if="!isBirthday(member)"
            :initials="getInitials(member)"
            size="lg"
          />
          <span
            v-else
            class="inline-flex size-12 shrink-0 animate-bounce items-center justify-center rounded-full bg-amber-300 text-lg font-semibold text-amber-900 ring-4 ring-amber-400/50 dark:bg-amber-500 dark:text-amber-950 dark:ring-amber-500/50"
          >
            🎂
          </span>
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <h2
                data-testid="member-name"
                class="text-ink truncate text-lg font-semibold"
              >
                {{ member.name || 'No name' }}
              </h2>
              <select
                v-if="canChangeRole(member)"
                data-testid="member-role-select"
                :value="member.role"
                class="focus-visible:outline-focus inline-flex shrink-0 cursor-pointer items-center rounded-full border-0 px-2 py-0.5 text-xs font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
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
                  v-for="role in availableRolesFor(member)"
                  :key="role"
                  :value="role"
                >
                  {{ role }}
                </option>
              </select>
              <AppBadge
                v-else-if="member.role"
                data-testid="member-role"
                :variant="
                  member.role === 'owner'
                    ? 'pending'
                    : member.role === 'admin'
                      ? 'info'
                      : 'neutral'
                "
              >
                {{ member.role }}
              </AppBadge>
            </div>
            <p
              v-if="isBirthday(member)"
              class="birthday-shimmer text-sm font-bold"
            >
              🎉 Happy Birthday! 🎉
            </p>
            <p
              data-testid="member-email"
              class="text-ink-muted truncate text-sm"
            >
              {{ member.email }}
            </p>
            <p
              v-if="member.birthday && !isBirthday(member)"
              class="text-ink-muted flex items-center gap-1 text-sm"
            >
              <CakeIcon class="size-3.5" />
              {{ formatBirthday(member.birthday) }}
            </p>
          </div>
        </div>

        <!-- Bottom section: action buttons -->
        <div class="border-line flex items-center gap-1 border-t px-5 py-3">
          <a
            :href="`mailto:${member.email}`"
            class="text-ink hover:bg-btn-secondary-fill focus-visible:outline-focus inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            <EnvelopeIcon class="size-4" />
            Email
          </a>
          <a
            v-if="member.phoneNumber"
            :href="`tel:${member.phoneNumber}`"
            class="text-ink hover:bg-btn-secondary-fill focus-visible:outline-focus inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            <PhoneIcon class="size-4" />
            Call
          </a>
          <button
            data-testid="download-vcard-button"
            class="text-ink hover:bg-btn-secondary-fill focus-visible:outline-focus ml-auto inline-flex cursor-pointer items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2"
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
