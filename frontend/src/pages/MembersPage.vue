<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import {
  UserIcon,
  UsersIcon,
  EnvelopeIcon,
  PhoneIcon,
  CakeIcon,
  IdentificationIcon,
  Cog6ToothIcon,
} from '@heroicons/vue/24/outline'
import { useMembersStore } from '@/stores'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import AppBadge from '@/components/common/AppBadge.vue'
import AppAvatar from '@/components/common/AppAvatar.vue'
import type { PoolMember } from '@/types/pool'
import { can } from '@/composables/usePermission'
import { formatBirthday, daysUntilBirthday } from '@/utils/date'
import { generateVCard, downloadVCard } from '@/utils/vcard'
import { getInitials } from '@/utils/member'

const membersStore = useMembersStore()
const { members } = storeToRefs(membersStore)
const authStore = useAuthStore()
const workspaceStore = useWorkspaceStore()

// This page is the directory — who's here and how to reach them. Inviting,
// chasing invitations and changing roles all sit behind the admin bar, so
// they live in the workspace's settings; admins get a link across rather
// than a second copy of the controls.
const manageMembersLink = computed(() =>
  can(workspaceStore.currentWorkspace?.permissions, 'manage_members')
    ? `/settings/workspaces/${workspaceStore.currentWorkspaceId}/members`
    : null
)

function isBirthday(member: PoolMember): boolean {
  return daysUntilBirthday(member.birthday) === 0
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
</script>

<template>
  <div>
    <PageHeader title="Members" :icon="UsersIcon" data-testid="page-title">
      <RouterLink
        v-if="manageMembersLink"
        :to="manageMembersLink"
        data-testid="manage-members-link"
        class="text-ink hover:bg-btn-secondary-fill focus-visible:outline-focus inline-flex min-h-[44px] shrink-0 items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 sm:min-h-0"
      >
        <Cog6ToothIcon class="size-4" />
        Manage members
      </RouterLink>
    </PageHeader>

    <EmptyState
      v-if="members.length === 0"
      :icon="UserIcon"
      heading="No members yet"
      description="People you add to this workspace will show up here."
    />

    <div
      v-else
      data-testid="members-list"
      class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3"
    >
      <BaseCard
        v-for="member in members"
        :key="member.id"
        :data-testid="`member-item-${member.id}`"
        :variant="
          member.userId === authStore.currentUserId && !isBirthday(member)
            ? 'self'
            : 'default'
        "
        class="row-span-2 grid grid-rows-subgrid"
        :class="isBirthday(member) && 'birthday-card'"
      >
        <!-- Top section: avatar + identity -->
        <div class="relative flex items-start gap-4 p-5">
          <div
            v-if="isBirthday(member)"
            class="pointer-events-none absolute inset-x-0 top-0 flex justify-between px-3 pt-1 text-xl"
          >
            <!-- The bob is staggered per emoji from CSS, not a style
                 attribute: these were the last inline styles in the app, and
                 the CSP can only drop style-src 'unsafe-inline' without
                 them. -->
            <span class="birthday-float">🎉</span>
            <span class="birthday-float">🎈</span>
            <span class="birthday-float">🎊</span>
            <span class="birthday-float">🥳</span>
            <span class="birthday-float">🎂</span>
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
              <AppBadge
                v-if="member.role"
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
  </div>
</template>

<style scoped>
.birthday-card {
  background: linear-gradient(
    135deg,
    var(--color-amber-100) 0%,
    var(--color-pink-100) 25%,
    var(--color-violet-100) 50%,
    var(--color-blue-100) 75%,
    var(--color-amber-100) 100%
  );
  background-size: 300% 300%;
  animation: birthday-gradient 4s ease infinite;
  box-shadow:
    0 0 15px color-mix(in oklab, var(--color-amber-400) 40%, transparent),
    0 0 30px color-mix(in oklab, var(--color-pink-400) 20%, transparent);
}

:where(.dark) .birthday-card {
  background: linear-gradient(
    135deg,
    var(--color-amber-900) 0%,
    var(--color-pink-900) 25%,
    var(--color-violet-950) 50%,
    var(--color-blue-950) 75%,
    var(--color-amber-900) 100%
  );
  background-size: 300% 300%;
  animation: birthday-gradient 4s ease infinite;
  box-shadow:
    0 0 15px color-mix(in oklab, var(--color-amber-400) 30%, transparent),
    0 0 30px color-mix(in oklab, var(--color-pink-400) 15%, transparent);
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

/* Deliberately not in source order — the row reads better when neighbouring
   emoji aren't in step, and this is the same stagger the inline
   animation-delay attributes used to carry. */
.birthday-float:nth-child(2) {
  animation-delay: 0.4s;
}

.birthday-float:nth-child(3) {
  animation-delay: 0.8s;
}

.birthday-float:nth-child(4) {
  animation-delay: 0.2s;
}

.birthday-float:nth-child(5) {
  animation-delay: 0.6s;
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
    var(--color-amber-500),
    var(--color-pink-500),
    var(--color-violet-500),
    var(--color-amber-500),
    var(--color-pink-500)
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
