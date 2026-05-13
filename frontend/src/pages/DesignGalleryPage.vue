<script setup lang="ts">
import { ref } from 'vue'
import {
  ArrowTopRightOnSquareIcon,
  CalendarDaysIcon,
  CheckCircleIcon,
  CurrencyEuroIcon,
  ExclamationTriangleIcon,
  InboxIcon,
  PencilSquareIcon,
  SwatchIcon,
  TrashIcon,
  WindowIcon,
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
import LedgerAmount from '@/components/common/LedgerAmount.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import TimeAnchor from '@/components/common/TimeAnchor.vue'
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
import GalleryGroup from '@/pages/design-gallery/GalleryGroup.vue'
import GallerySection from '@/pages/design-gallery/GallerySection.vue'
import GalleryTOC from '@/pages/design-gallery/GalleryTOC.vue'
import type { TOCItem } from '@/pages/design-gallery/types'
import ColorTokens from '@/pages/design-gallery/ColorTokens.vue'
import TypographySpecimen from '@/pages/design-gallery/TypographySpecimen.vue'
import SpacingSpecimen from '@/pages/design-gallery/SpacingSpecimen.vue'

const text = ref('Lisbon weekend')
const errorText = ref('lisbon weekend!!')
const selectValue = ref('weekend')
const radioValue = ref('a')
const checked = ref(true)
const toggleOn = ref(true)
const modalOpen = ref(false)

// Live timestamps for the TimeAnchor showcase — sit mid-tier (e.g. 23m, 5h)
// rather than at boundaries so a snapshot taken a few seconds later still
// formats the same. Subsequent baseline refreshes will pick up the latest
// tier the wall clock has crossed into.
const renderedAt = Date.now()
const SECOND = 1_000
const MINUTE = 60 * SECOND
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR
const justNowTs = new Date(renderedAt - 20 * SECOND).toISOString()
const minutesAgoTs = new Date(renderedAt - 23 * MINUTE).toISOString()
const hoursAgoTs = new Date(renderedAt - 5 * HOUR).toISOString()
const daysAgoTs = new Date(renderedAt - 2 * DAY).toISOString()
const weeksAgoTs = new Date(renderedAt - 2 * 7 * DAY).toISOString()
const futureTs = new Date(renderedAt + 3 * HOUR).toISOString()

// Anchor map for the sticky TOC. Order here = order on the page. Every entry
// here is the `id` on a GallerySection below; keep them in sync or the TOC
// will silently lose a link.
const tocItems: TOCItem[] = [
  { group: 'Foundations', id: 'foundations-color', label: 'Color' },
  { group: 'Foundations', id: 'foundations-typography', label: 'Typography' },
  { group: 'Foundations', id: 'foundations-spacing', label: 'Spacing' },
  { group: 'Atoms', id: 'atoms-buttons', label: 'Buttons' },
  { group: 'Atoms', id: 'atoms-badges-avatars', label: 'Badges & avatars' },
  { group: 'Signatures', id: 'signatures-ledger', label: 'Ledger amounts' },
  { group: 'Signatures', id: 'signatures-time', label: 'Time anchors' },
  { group: 'Forms', id: 'forms-controls', label: 'Form controls' },
  { group: 'Containers', id: 'containers-cards', label: 'Cards' },
  { group: 'Containers', id: 'containers-alerts', label: 'Alerts' },
  { group: 'Containers', id: 'containers-empty', label: 'Empty state' },
  { group: 'Overlays', id: 'overlays-modal', label: 'Modal' },
]
</script>

<template>
  <div class="bg-surface-page text-ink min-h-screen">
    <div class="mx-auto max-w-[110rem] px-4 py-12 sm:px-6 lg:px-8">
      <PageHeader title="Design system" :icon="SwatchIcon">
        <template #subtitle>
          Every primitive in its meaningful states. The gallery is the system
          made visible — anything that drifts here drifts in production.
        </template>
        <div class="text-meta hidden items-center gap-4 sm:flex">
          <a
            href="https://github.com/iain/tayaway/blob/main/DESIGN.md"
            target="_blank"
            rel="noopener"
            class="focus-visible:outline-focus inline-flex items-center gap-1 text-cyan-600 underline hover:text-cyan-700 focus-visible:outline-2 focus-visible:outline-offset-2 dark:text-cyan-400 dark:hover:text-cyan-300"
          >
            DESIGN.md
            <ArrowTopRightOnSquareIcon class="size-3.5" aria-hidden="true" />
          </a>
          <a
            href="https://github.com/iain/tayaway/blob/main/PRODUCT.md"
            target="_blank"
            rel="noopener"
            class="focus-visible:outline-focus inline-flex items-center gap-1 text-cyan-600 underline hover:text-cyan-700 focus-visible:outline-2 focus-visible:outline-offset-2 dark:text-cyan-400 dark:hover:text-cyan-300"
          >
            PRODUCT.md
            <ArrowTopRightOnSquareIcon class="size-3.5" aria-hidden="true" />
          </a>
        </div>
      </PageHeader>

      <div class="lg:grid lg:grid-cols-[14rem_minmax(0,1fr)] lg:gap-10">
        <aside class="hidden lg:block">
          <div class="sticky top-8">
            <GalleryTOC :items="tocItems" />
          </div>
        </aside>

        <div class="space-y-section min-w-0">
          <GalleryGroup
            id="foundations"
            title="Foundations"
            description="The tokens every primitive is composed from — colours, type ramp, and the three named spacing roles."
          >
            <GallerySection
              id="foundations-color"
              title="Color"
              description="Tinted neutrals plus three saturated voices: amber for orientation, red for attention, cyan for navigation."
            >
              <ColorTokens />
            </GallerySection>

            <GallerySection
              id="foundations-typography"
              title="Typography"
              description="Inter Variable from page title to footnote. Hierarchy through scale and weight, never family."
            >
              <TypographySpecimen />
            </GallerySection>

            <GallerySection
              id="foundations-spacing"
              title="Spacing"
              description="The 4-px Tailwind scale, with three roles tokenised on top of it."
            >
              <SpacingSpecimen />
            </GallerySection>
          </GalleryGroup>

          <GalleryGroup
            id="atoms"
            title="Atoms"
            description="The smallest primitives — buttons, badges, avatars. Each block shows variants, sizes, and states."
          >
            <GallerySection
              id="atoms-buttons"
              title="Buttons"
              description="AppButton, TextButton, IconButton."
              motion="Press in, don't lift. Hover tints; active brightens by 5%. No translate, no scale, no bounce."
            >
              <SectionHeading :icon="PencilSquareIcon" title="Variants & sizes" />
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
                       interact with the row to see them. Visual regression
                       captures resting + disabled + loading across variants. -->
                  <div class="space-y-3">
                    <p
                      class="text-ink-faint mb-1 text-xs tracking-wide uppercase"
                    >
                      States — interact for hover and focus
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
            </GallerySection>

            <GallerySection
              id="atoms-badges-avatars"
              title="Badges & avatars"
              description="State badges and identity disks. Six state-named badge variants; three avatar variants."
            >
              <SectionHeading :icon="CheckCircleIcon" title="Variants" />
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
            </GallerySection>
          </GalleryGroup>

          <GalleryGroup
            id="signatures"
            title="Signature primitives"
            description="The system's three signature moves: the amber landmark icon, the ledger amount, the time anchor. Each carries the system's voice on its own."
          >
            <GallerySection
              id="signatures-ledger"
              title="Ledger amounts"
              description="Tabular figures, faint currency mark, optional direction sign. Locale-aware via Intl.NumberFormat."
            >
              <SectionHeading :icon="CurrencyEuroIcon" title="LedgerAmount" />
              <BaseCard padded>
                <div class="space-y-6">
                  <div class="flex flex-wrap items-baseline gap-x-6 gap-y-3">
                    <LedgerAmount :amount="42.5" />
                    <LedgerAmount :amount="42.5" direction="in" />
                    <LedgerAmount :amount="42.5" direction="out" />
                    <LedgerAmount :amount="1234.56" />
                    <LedgerAmount :amount="1234567.89" direction="out" />
                    <LedgerAmount :amount="0" />
                  </div>
                  <!-- Same amount across four locales so the locale-aware
                       separators, decimal style, and currency placement are
                       visible side-by-side. -->
                  <div>
                    <p
                      class="text-ink-faint mb-2 text-xs tracking-wide uppercase"
                    >
                      Same amount, four locales
                    </p>
                    <div class="grid max-w-md grid-cols-2 gap-x-6 gap-y-1">
                      <span class="text-ink-muted text-meta">en-US</span>
                      <LedgerAmount
                        :amount="1234.56"
                        direction="in"
                        locale="en-US"
                      />
                      <span class="text-ink-muted text-meta">nl-NL</span>
                      <LedgerAmount
                        :amount="1234.56"
                        direction="in"
                        locale="nl-NL"
                      />
                      <span class="text-ink-muted text-meta">fr-FR</span>
                      <LedgerAmount
                        :amount="1234.56"
                        direction="in"
                        locale="fr-FR"
                      />
                      <span class="text-ink-muted text-meta">de-DE</span>
                      <LedgerAmount
                        :amount="1234.56"
                        direction="in"
                        locale="de-DE"
                      />
                    </div>
                  </div>
                  <!-- A small ledger sketch so the tabular-figure alignment
                       and direction colouring read against each other. -->
                  <table class="text-body w-full max-w-sm border-collapse">
                    <thead>
                      <tr class="text-ink-muted text-meta">
                        <th class="pb-2 text-left font-medium">Member</th>
                        <th class="pb-2 text-right font-medium">Paid</th>
                        <th class="pb-2 text-right font-medium">Balance</th>
                      </tr>
                    </thead>
                    <tbody class="text-ink">
                      <tr>
                        <td class="py-1">Daisy</td>
                        <td class="text-ink-muted py-1 text-right">
                          <LedgerAmount :amount="80" />
                        </td>
                        <td class="py-1 text-right">
                          <LedgerAmount :amount="15.5" direction="in" />
                        </td>
                      </tr>
                      <tr>
                        <td class="py-1">Iain</td>
                        <td class="text-ink-muted py-1 text-right">
                          <LedgerAmount :amount="42.5" />
                        </td>
                        <td class="py-1 text-right">
                          <LedgerAmount :amount="9.25" direction="out" />
                        </td>
                      </tr>
                      <tr>
                        <td class="py-1">Joep</td>
                        <td class="text-ink-muted py-1 text-right">
                          <LedgerAmount :amount="0" />
                        </td>
                        <td class="text-ink-faint py-1 text-right">even</td>
                      </tr>
                      <tr class="border-line border-t">
                        <td class="pt-2 font-semibold">Total</td>
                        <td
                          class="text-ink-muted pt-2 text-right font-semibold"
                        >
                          <LedgerAmount :amount="122.5" />
                        </td>
                        <td class="pt-2"></td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </BaseCard>
            </GallerySection>

            <GallerySection
              id="signatures-time"
              title="Time anchors"
              description="Compact unit voice (m/h/d/w), verb-anchored, live-ticking from the shared minute clock."
              motion="Live-ticking via the shared minute clock — 23m becomes 24m without a refresh, and every TimeAnchor on the page agrees on what 'now' means."
            >
              <SectionHeading :icon="InboxIcon" title="TimeAnchor" />
              <BaseCard padded>
                <div class="text-meta space-y-4">
                  <div class="text-ink-muted">
                    <p class="text-ink-faint text-xs tracking-wide uppercase">
                      Tiers
                    </p>
                    <div class="mt-2 grid grid-cols-2 gap-x-6 gap-y-1">
                      <span>under a minute</span>
                      <TimeAnchor :at="justNowTs" />
                      <span>under an hour</span>
                      <TimeAnchor :at="minutesAgoTs" />
                      <span>under a day</span>
                      <TimeAnchor :at="hoursAgoTs" />
                      <span>under a week</span>
                      <TimeAnchor :at="daysAgoTs" />
                      <span>under four weeks</span>
                      <TimeAnchor :at="weeksAgoTs" />
                      <span>future</span>
                      <TimeAnchor :at="futureTs" />
                    </div>
                  </div>
                  <div class="text-ink-muted">
                    <p class="text-ink-faint text-xs tracking-wide uppercase">
                      Anchored to a verb
                    </p>
                    <ul class="mt-2 space-y-1">
                      <li>
                        <TimeAnchor :at="minutesAgoTs">Last synced</TimeAnchor>
                      </li>
                      <li>
                        <TimeAnchor :at="hoursAgoTs">Daisy paid</TimeAnchor>
                      </li>
                      <li>
                        <TimeAnchor :at="daysAgoTs">Sent</TimeAnchor>
                      </li>
                      <li>
                        <TimeAnchor :at="futureTs">Expires</TimeAnchor>
                      </li>
                    </ul>
                  </div>
                </div>
              </BaseCard>
            </GallerySection>
          </GalleryGroup>

          <GalleryGroup
            id="forms"
            title="Forms"
            description="Inputs, selection controls, and the patterns they compose into."
          >
            <GallerySection
              id="forms-controls"
              title="Form controls"
              description="Every form primitive in its meaningful states. Errors use the danger outline; disabled drops opacity to 50%."
            >
              <template #default="{ mode }">
                <SectionHeading :icon="PencilSquareIcon" title="Controls" />
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
              </template>
            </GallerySection>
          </GalleryGroup>

          <GalleryGroup
            id="containers"
            title="Containers and surfaces"
            description="Cards, alerts, and the empty-state pattern. Containers carry content; their job is to be calm."
          >
            <GallerySection
              id="containers-cards"
              title="Cards"
              description="Default, action, urgent, and the interactive variant. Hover lifts only the interactive one."
              motion="Interactive cards add a 2px ring on hover and a 5% brightness shift on active. Never scale or translate."
            >
              <SectionHeading :icon="InboxIcon" title="Variants" />
              <div class="space-y-4">
                <BaseCard padded>
                  <h4 class="text-ink font-semibold">Default</h4>
                  <p class="text-ink-muted text-sm">
                    White surface, hairline ring, hairline shadow.
                  </p>
                </BaseCard>
                <BaseCard padded variant="action">
                  <h4 class="text-ink font-semibold">Action</h4>
                  <p class="text-ink-muted text-sm">
                    3 votes waiting. Decide on dates so the group can lock in.
                  </p>
                </BaseCard>
                <BaseCard padded variant="urgent">
                  <h4 class="text-ink font-semibold">Urgent</h4>
                  <p class="text-ink-muted text-sm">
                    Settlement overdue by 4 days.
                  </p>
                </BaseCard>
                <BaseCard padded interactive>
                  <h4 class="text-ink font-semibold">Interactive</h4>
                  <p class="text-ink-muted text-sm">
                    Hover to see the rose ring affordance.
                  </p>
                </BaseCard>
              </div>
            </GallerySection>

            <GallerySection
              id="containers-alerts"
              title="Alerts"
              description="Banner-level messages for connection, sync, and confirmation. Errors interrupt; success and warning queue politely."
            >
              <SectionHeading :icon="ExclamationTriangleIcon" title="AlertBox" />
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
            </GallerySection>

            <GallerySection
              id="containers-empty"
              title="Empty state"
              description="A region body, not a card child. The amber landmark icon at 48px announces the missing region."
            >
              <SectionHeading :icon="CalendarDaysIcon" title="EmptyState" />
              <div class="ring-ring-hairline rounded-lg ring-1">
                <EmptyState
                  :icon="CalendarDaysIcon"
                  heading="No events yet"
                  description="Create one to start coordinating with the group."
                >
                  <AppButton>Plan an event</AppButton>
                </EmptyState>
              </div>
            </GallerySection>
          </GalleryGroup>

          <GalleryGroup
            id="overlays"
            title="Overlays"
            description="Surfaces that lift above the page — modals, toasts, popovers."
          >
            <GallerySection
              id="overlays-modal"
              title="Modal"
              description="Native &lt;dialog&gt; with showModal(). The only place the system genuinely lifts."
              motion="200ms cubic-bezier(0.25, 1, 0.5, 1) — fades, slides 8px up, scales from 0.98. prefers-reduced-motion collapses to 0.01ms."
            >
              <SectionHeading :icon="WindowIcon" title="BaseModal" />
              <BaseCard padded>
                <p class="text-ink-muted mb-4 text-sm">
                  Opens a global overlay; toggle the app's mode to see it dark.
                </p>
                <AppButton @click="modalOpen = true">Open modal</AppButton>
              </BaseCard>
            </GallerySection>
          </GalleryGroup>
        </div>
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
