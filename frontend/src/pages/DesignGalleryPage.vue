<script setup lang="ts">
import { ref } from 'vue'
import {
  CalendarDaysIcon,
  CheckCircleIcon,
  ExclamationTriangleIcon,
  InboxIcon,
  PencilSquareIcon,
  TrashIcon,
  XCircleIcon,
} from '@heroicons/vue/24/outline'
import AlertBox from '@/components/common/AlertBox.vue'
import AppAvatar from '@/components/common/AppAvatar.vue'
import AppBadge from '@/components/common/AppBadge.vue'
import AppButton from '@/components/common/AppButton.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import BaseModal from '@/components/common/BaseModal.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import IconButton from '@/components/common/IconButton.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import TextButton from '@/components/common/TextButton.vue'
import {
  FormCheckbox,
  FormInput,
  FormRadioGroup,
  FormSelect,
} from '@/components/form'
import FormToggle from '@/components/form/FormToggle.vue'
import FormTextarea from '@/components/form/FormTextarea.vue'

const text = ref('Lisbon weekend')
const errorText = ref('lisbon weekend!!')
const selectValue = ref('weekend')
const radioValue = ref('a')
const checked = ref(true)
const toggleOn = ref(true)
const modalOpen = ref(false)
</script>

<template>
  <div class="bg-surface-page text-ink min-h-screen">
    <div class="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8">
      <PageHeader title="Design system">
        <template #subtitle>
          Every primitive in its meaningful states. The gallery is the system
          made visible — anything that drifts here drifts in production.
        </template>
      </PageHeader>

      <!-- Light / dark side-by-side. Each section explicitly scopes its own
           mode so the gallery survives the app being in dark mode globally
           — see the `.light`/`.dark` definitions in style.css. -->
      <div class="grid gap-8 lg:grid-cols-2">
        <section
          v-for="mode in ['light', 'dark']"
          :key="mode"
          :class="[
            mode,
            'bg-surface-page text-ink ring-ring-hairline rounded-lg p-6 ring-1',
          ]"
          :data-mode="mode"
        >
          <h2
            class="text-ink-muted mb-6 text-sm font-semibold tracking-wide uppercase"
          >
            {{ mode }}
          </h2>

          <!-- Buttons -->
          <SectionHeading :icon="PencilSquareIcon" title="Buttons" />
          <BaseCard padded>
            <div class="space-y-6">
              <div class="flex flex-wrap items-center gap-2">
                <AppButton variant="primary">Save changes</AppButton>
                <AppButton variant="secondary">Cancel</AppButton>
                <AppButton variant="amber">Continue</AppButton>
                <AppButton variant="inflow">Mark received</AppButton>
                <AppButton variant="outflow">Pay via QR</AppButton>
                <AppButton variant="danger">Delete</AppButton>
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <AppButton size="sm">Small</AppButton>
                <AppButton size="md">Medium</AppButton>
                <AppButton size="lg">Large</AppButton>
              </div>
              <!-- State matrix. Hover/focus are live affordances - reviewers
                   interact with the row to see them. Visual regression captures
                   the resting + disabled + loading states across variants. -->
              <div class="space-y-3">
                <p
                  class="text-ink-faint mb-1 text-xs tracking-wide uppercase"
                >
                  States · hover &amp; focus me
                </p>
                <div
                  v-for="state in ['primary', 'secondary', 'danger'] as const"
                  :key="state"
                  class="flex flex-wrap items-center gap-2"
                >
                  <span class="text-ink-muted w-20 shrink-0 text-xs">
                    {{ state }}
                  </span>
                  <AppButton :variant="state">Rest</AppButton>
                  <AppButton :variant="state" :disabled="true"
                    >Disabled</AppButton
                  >
                  <AppButton
                    :variant="state"
                    :loading="true"
                    loading-label="Saving"
                    >Loading</AppButton
                  >
                </div>
              </div>
              <div class="flex flex-wrap items-center gap-3">
                <TextButton>View all events</TextButton>
                <TextButton variant="secondary">Dismiss</TextButton>
                <TextButton variant="danger">Remove</TextButton>
              </div>
              <div class="flex items-center gap-2">
                <IconButton label="Edit">
                  <PencilSquareIcon class="size-5" />
                </IconButton>
                <IconButton label="Delete" variant="danger">
                  <TrashIcon class="size-5" />
                </IconButton>
              </div>
            </div>
          </BaseCard>

          <!-- Cards -->
          <div class="mt-8">
            <SectionHeading :icon="InboxIcon" title="Cards" />
            <div class="space-y-4">
              <BaseCard padded>
                <h3 class="font-semibold">Default</h3>
                <p class="text-ink-muted text-sm">
                  White surface, hairline ring, hairline shadow.
                </p>
              </BaseCard>
              <BaseCard padded variant="action">
                <h3 class="font-semibold">Action</h3>
                <p class="text-ink-muted text-sm">
                  3 votes waiting. Decide on dates so the group can lock in.
                </p>
              </BaseCard>
              <BaseCard padded variant="urgent">
                <h3 class="font-semibold">Urgent</h3>
                <p class="text-ink-muted text-sm">
                  Settlement overdue by 4 days.
                </p>
              </BaseCard>
              <BaseCard padded interactive>
                <h3 class="font-semibold">Interactive</h3>
                <p class="text-ink-muted text-sm">
                  Hover to see the rose ring affordance.
                </p>
              </BaseCard>
            </div>
          </div>

          <!-- Inputs -->
          <div class="mt-8">
            <SectionHeading :icon="PencilSquareIcon" title="Forms" />
            <BaseCard padded>
              <div class="space-y-6">
                <FormInput
                  :id="`gallery-input-${mode}`"
                  v-model="text"
                  label="Event name"
                  placeholder="e.g. Lisbon weekend"
                />
                <FormInput
                  :id="`gallery-input-prefix-${mode}`"
                  v-model="text"
                  label="Trip URL"
                  prefix="tayaway.com/"
                />
                <FormTextarea
                  :id="`gallery-textarea-${mode}`"
                  v-model="text"
                  label="Notes"
                  placeholder="Anything the group should know"
                />
                <FormSelect
                  :id="`gallery-select-${mode}`"
                  v-model="selectValue"
                  label="Trip length"
                  :options="[
                    { value: 'day', label: 'Day trip' },
                    { value: 'weekend', label: 'Weekend' },
                    { value: 'week', label: 'Week or longer' },
                  ]"
                />
                <FormCheckbox
                  :id="`gallery-checkbox-${mode}`"
                  v-model="checked"
                  label="Notify the group"
                  description="Send a push when the date is locked in."
                />
                <FormToggle
                  :id="`gallery-toggle-${mode}`"
                  v-model="toggleOn"
                  label="Auto-settle expenses"
                  description="Mark balances paid when the group confirms."
                />
                <FormRadioGroup
                  v-model="radioValue"
                  :name="`gallery-radio-${mode}`"
                  legend="Send timing"
                  description="When the group should be pinged."
                  :options="[
                    { id: 'a', label: 'Right away' },
                    { id: 'b', label: 'Daily digest' },
                    { id: 'c', label: 'Weekly digest' },
                  ]"
                />
                <FormInput
                  :id="`gallery-input-error-${mode}`"
                  v-model="errorText"
                  label="Trip URL"
                  error="URL can only contain letters, numbers, and dashes."
                />
                <FormInput
                  :id="`gallery-input-disabled-${mode}`"
                  v-model="text"
                  label="Locked field"
                  :disabled="true"
                />
                <div class="flex flex-wrap gap-x-6 gap-y-3">
                  <FormCheckbox
                    :id="`gallery-checkbox-disabled-${mode}`"
                    v-model="checked"
                    label="Disabled, checked"
                    :disabled="true"
                  />
                  <FormToggle
                    :id="`gallery-toggle-disabled-${mode}`"
                    v-model="toggleOn"
                    label="Disabled toggle"
                    :disabled="true"
                  />
                </div>
              </div>
            </BaseCard>
          </div>

          <!-- Badges + Avatars -->
          <div class="mt-8">
            <SectionHeading
              :icon="CheckCircleIcon"
              title="Badges &amp; avatars"
            />
            <BaseCard padded>
              <div class="space-y-4">
                <div class="flex flex-wrap gap-2">
                  <AppBadge variant="success">Decided</AppBadge>
                  <AppBadge variant="pending">Voting</AppBadge>
                  <AppBadge variant="warning">Stale</AppBadge>
                  <AppBadge variant="danger">Overdue</AppBadge>
                  <AppBadge variant="info">Synced</AppBadge>
                  <AppBadge variant="neutral">Draft</AppBadge>
                </div>
                <div class="flex items-center gap-2">
                  <AppAvatar initials="IK" size="sm" />
                  <AppAvatar initials="JM" />
                  <AppAvatar initials="RW" size="lg" />
                  <AppAvatar initials="SB" variant="pending" />
                </div>
              </div>
            </BaseCard>
          </div>

          <!-- Alerts -->
          <div class="mt-8">
            <SectionHeading :icon="ExclamationTriangleIcon" title="Alerts" />
            <div class="space-y-4">
              <AlertBox variant="error" :icon="XCircleIcon">
                Couldn't save changes — the connection dropped.
              </AlertBox>
              <AlertBox variant="warning" :icon="ExclamationTriangleIcon">
                Last sync was 3 hours ago. Some balances may be stale.
              </AlertBox>
              <AlertBox variant="success" :icon="CheckCircleIcon">
                Payment recorded. The group has been notified.
              </AlertBox>
            </div>
          </div>

          <!-- Empty state -->
          <div class="mt-8">
            <SectionHeading :icon="CalendarDaysIcon" title="Empty state" />
            <BaseCard padded>
              <EmptyState
                :icon="CalendarDaysIcon"
                heading="No events yet"
                description="Create one to start coordinating with the group."
              >
                <AppButton>Plan an event</AppButton>
              </EmptyState>
            </BaseCard>
          </div>

          <!-- Modal trigger. The dialog renders outside this column's
               light/dark scope, so it always opens in the app's global mode -
               but a trigger lives in both columns so the gallery stays
               symmetric. -->
          <div class="mt-8">
            <SectionHeading :icon="PencilSquareIcon" title="Modal" />
            <BaseCard padded>
              <p class="text-ink-muted mb-4 text-sm">
                Opens a global overlay; toggle the app's mode to see it dark.
              </p>
              <AppButton @click="modalOpen = true">Open modal</AppButton>
            </BaseCard>
          </div>

          <!-- Motion. Per-mode because hover tints and brightness shifts
               read differently against light vs dark surfaces. The modal
               trigger lives once in the light column above since the dialog
               itself renders outside this scope. -->
          <div class="mt-8">
            <SectionHeading :icon="PencilSquareIcon" title="Motion" />
            <BaseCard padded>
              <div class="space-y-6">
                <div>
                  <p class="text-ink-muted mb-2 text-sm">
                    Press &amp; hover - press-don't-lift: actives push
                    <em>in</em>, hovers tint, neither translate.
                  </p>
                  <div class="flex flex-wrap items-center gap-2">
                    <AppButton variant="primary">Save changes</AppButton>
                    <AppButton variant="secondary">Cancel</AppButton>
                    <AppButton variant="danger">Delete</AppButton>
                  </div>
                </div>
                <div>
                  <p class="text-ink-muted mb-2 text-sm">
                    Interactive card - rose ring on hover, brightness shift on
                    active.
                  </p>
                  <BaseCard padded interactive>
                    <h3 class="font-semibold">Hover me</h3>
                    <p class="text-ink-muted text-sm">
                      The ring is the affordance; no shadow change, no scale.
                    </p>
                  </BaseCard>
                </div>
              </div>
            </BaseCard>
          </div>
        </section>
      </div>
    </div>

    <BaseModal
      :open="modalOpen"
      title="Confirm delete"
      @close="modalOpen = false"
    >
      <p class="text-ink-muted">
        This will remove the event for everyone in the group. This can't be
        undone.
      </p>
      <div class="mt-6 flex justify-end gap-2">
        <AppButton variant="secondary" @click="modalOpen = false"
          >Cancel</AppButton
        >
        <AppButton variant="danger" @click="modalOpen = false"
          >Delete</AppButton
        >
      </div>
    </BaseModal>
  </div>
</template>
