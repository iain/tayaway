<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import {
  UsersIcon,
  PlusIcon,
  EnvelopeIcon,
  XMarkIcon,
  ArrowPathIcon,
} from '@heroicons/vue/24/outline'
import { ChevronDownIcon } from '@heroicons/vue/16/solid'
import { useMembersStore, useNotificationsStore } from '@/stores'
import { useObjectPoolStore } from '@/stores/objectPool'
import InviteMemberModal from '@/components/members/InviteMemberModal.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
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
import { isPastIso, addHours, formatClockTime } from '@/utils/date'
import { getInitials } from '@/utils/member'

const route = useRoute()
const membersStore = useMembersStore()
const pool = useObjectPoolStore()

const workspaceId = computed(() => String(route.params.id ?? ''))
const workspace = computed(() => pool.get('workspace', workspaceId.value))
const members = computed(() => membersStore.membersIn(workspaceId.value))
const pendingInvites = computed(() =>
  membersStore.pendingInvitesIn(workspaceId.value)
)

const isModalOpen = ref(false)
const isSubmitting = ref(false)
const remindingInviteId = ref<string | null>(null)
const cancellingInviteId = ref<string | null>(null)
const formError = ref<string | null>(null)
const roleError = ref<string | null>(null)

// Settings reaches workspaces this client isn't subscribed to, whose roster
// the pool therefore only knows us from. Ask for the rest.
function load(): void {
  membersStore.fetchMembers(workspaceId.value)
  membersStore.fetchInvites(workspaceId.value)
}

onMounted(load)
watch(workspaceId, load)

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
    await membersStore.createInvite(email, name || undefined, workspaceId.value)
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

async function handleCancelInvite(id: string): Promise<void> {
  if (cancellingInviteId.value === id) return
  cancellingInviteId.value = id
  try {
    await membersStore.cancelInvite(id, workspaceId.value)
  } catch {
    const notifications = useNotificationsStore()
    notifications.showError('Could not cancel invitation. Please try again.')
  } finally {
    cancellingInviteId.value = null
  }
}

// Reminders are gated behind a 24h cooldown from the last send (or the invite's
// creation, if none was sent yet).
const REMIND_COOLDOWN_HOURS = 24

function isExpired(invite: PoolWorkspaceInvite): boolean {
  return isPastIso(invite.expiresAt)
}

function remindCooldownUntil(invite: PoolWorkspaceInvite): string {
  return addHours(
    invite.lastRemindedAt ?? invite.createdAt,
    REMIND_COOLDOWN_HOURS
  )
}

function canRemind(invite: PoolWorkspaceInvite): boolean {
  return isPastIso(remindCooldownUntil(invite))
}

function remindAvailableAt(invite: PoolWorkspaceInvite): string {
  return formatClockTime(remindCooldownUntil(invite))
}

async function handleRemind(id: string): Promise<void> {
  remindingInviteId.value = id
  try {
    await membersStore.sendReminder(id, workspaceId.value)
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
</script>

<template>
  <div>
    <SectionHeading :icon="UsersIcon" title="Members">
      <AppButton
        v-if="workspace"
        variant="secondary"
        size="sm"
        data-testid="invite-member-button"
        @click="openModal"
      >
        <PlusIcon class="size-5" />
        Invite Member
      </AppButton>
    </SectionHeading>

    <EmptyState
      v-if="!workspace"
      :icon="UsersIcon"
      heading="Workspace not found"
      description="You may no longer be a member of it."
    />

    <template v-else>
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
        <h3
          class="text-ink-muted mb-3 text-sm font-semibold tracking-wide uppercase"
        >
          Pending Invitations
        </h3>
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
                  <EnvelopeIcon class="text-ink-muted mr-3 size-8 shrink-0" />
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
                    <div
                      class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1"
                    >
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
                      :class="{
                        'animate-spin': remindingInviteId === invite.id,
                      }"
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

      <BaseCard padded>
        <ul class="divide-line divide-y" data-testid="workspace-members">
          <li
            v-for="member in members"
            :key="member.id"
            :data-testid="`workspace-member-${member.id}`"
            class="flex items-center gap-3 py-3 first:pt-0 last:pb-0"
          >
            <AppAvatar :initials="getInitials(member)" />
            <div class="min-w-0 flex-1">
              <p class="text-ink truncate text-sm font-medium">
                {{ member.name || 'No name' }}
              </p>
              <p class="text-ink-muted truncate text-sm">{{ member.email }}</p>
            </div>
            <!-- Same shell as FormSelect, minus its stacked label: in a
                 settings row the person's name is the label. -->
            <div v-if="canChangeRole(member)" class="grid shrink-0 grid-cols-1">
              <select
                :aria-label="`Role for ${member.name || member.email}`"
                data-testid="member-role-select"
                :value="member.role"
                class="bg-surface-sunken outline-line focus:outline-focus text-ink *:bg-surface col-start-1 row-start-1 cursor-pointer appearance-none rounded-md py-1 pr-8 pl-3 text-sm outline-1 -outline-offset-1 focus:outline-2 focus:outline-offset-2"
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
              <ChevronDownIcon
                class="text-ink-muted pointer-events-none col-start-1 row-start-1 mr-2 size-4 self-center justify-self-end"
                aria-hidden="true"
              />
            </div>
            <!-- Roles you can't change read as plain text, not as a control
                 you're forbidden to touch. -->
            <span
              v-else-if="member.role"
              data-testid="member-role"
              class="text-ink-muted shrink-0 px-3 py-1 text-sm"
            >
              {{ member.role }}
            </span>
          </li>
        </ul>
      </BaseCard>
    </template>

    <InviteMemberModal
      :open="isModalOpen"
      :loading="isSubmitting"
      @close="closeModal"
      @save="handleSave"
    />
  </div>
</template>
