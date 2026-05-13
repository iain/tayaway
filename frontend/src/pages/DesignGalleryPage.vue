<script setup lang="ts">
import { ref } from 'vue'
import {
  ArrowPathIcon,
  ArrowTopRightOnSquareIcon,
  Bars3BottomLeftIcon,
  BanknotesIcon,
  BookmarkIcon,
  CalendarDaysIcon,
  CalendarIcon,
  CheckCircleIcon,
  ClipboardDocumentListIcon,
  ClockIcon,
  CurrencyEuroIcon,
  ExclamationTriangleIcon,
  IdentificationIcon,
  MapPinIcon,
  MegaphoneIcon,
  PencilSquareIcon,
  RectangleStackIcon,
  Squares2X2Icon,
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
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import DefinitionRow from '@/components/common/DefinitionRow.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import IconButton from '@/components/common/IconButton.vue'
import LedgerAmount from '@/components/common/LedgerAmount.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import TimeAnchor from '@/components/common/TimeAnchor.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import TextButton from '@/components/common/TextButton.vue'
import ToastNotification from '@/components/common/ToastNotification.vue'
import {
  FormActions,
  FormCheckbox,
  FormInput,
  FormRadioGroup,
  FormSection,
  FormSelect,
} from '@/components/form'
import CurrencyInput from '@/components/form/CurrencyInput.vue'
import FormToggle from '@/components/form/FormToggle.vue'
import FormTextarea from '@/components/form/FormTextarea.vue'
import LocationInput from '@/components/form/LocationInput.vue'
import GalleryGroup from '@/pages/design-gallery/GalleryGroup.vue'
import GalleryRule from '@/pages/design-gallery/GalleryRule.vue'
import GallerySection from '@/pages/design-gallery/GallerySection.vue'
import GalleryTOC from '@/pages/design-gallery/GalleryTOC.vue'
import GalleryTOCMobile from '@/pages/design-gallery/GalleryTOCMobile.vue'
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
const currency = ref('42.50')
const location = ref('')
const locationLat = ref<number | null>(null)
const locationLng = ref<number | null>(null)

const composedText = ref('Lisbon weekend')
const composedCurrency = ref('250.00')
const composedToggle = ref(true)

// One ref for every modal width; openModalSize names the active variant or
// null. The five buttons share the same dialog instance and just swap which
// size class the modal applies.
type ModalSize = 'sm' | 'md' | 'lg' | 'xl' | '2xl'
const openModalSize = ref<ModalSize | null>(null)
const confirmOpen = ref(false)
const formModalOpen = ref(false)
const modalText = ref('Lisbon weekend')

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

const today = new Date()
const nextWeek = new Date(today.getTime() + 7 * DAY)
const startIso = today.toISOString().slice(0, 10)
const endIso = nextWeek.toISOString().slice(0, 10)
const sameDayIso = today.toISOString().slice(0, 10)

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
  { group: 'Signatures', id: 'signatures-daterange', label: 'Date ranges' },
  { group: 'Forms', id: 'forms-controls', label: 'Form controls' },
  { group: 'Forms', id: 'forms-currency', label: 'Currency input' },
  { group: 'Forms', id: 'forms-location', label: 'Location input' },
  { group: 'Forms', id: 'forms-composition', label: 'Form composition' },
  { group: 'Containers', id: 'containers-cards', label: 'Cards' },
  { group: 'Containers', id: 'containers-alerts', label: 'Alerts' },
  { group: 'Containers', id: 'containers-empty', label: 'Empty state' },
  { group: 'Containers', id: 'containers-definition', label: 'Definition row' },
  { group: 'Landmarks', id: 'landmarks-page', label: 'Page header' },
  { group: 'Landmarks', id: 'landmarks-section', label: 'Section heading' },
  { group: 'Overlays', id: 'overlays-modal', label: 'Modal' },
  { group: 'Overlays', id: 'overlays-toast', label: 'Toast' },
  { group: 'Overlays', id: 'overlays-updatepill', label: 'Update pill' },
]

const toastInfo = {
  id: 'demo-info',
  type: 'info' as const,
  message: 'Daisy joined the trip.',
}
const toastError = {
  id: 'demo-error',
  type: 'error' as const,
  message: "Couldn't save your edit — try again in a moment.",
}
const toastAction = {
  id: 'demo-action',
  type: 'info' as const,
  message: 'New version available.',
  actionLabel: 'Refresh',
  action: () => {
    /* demo only */
  },
}
const updatePill = {
  id: 'demo-update',
  type: 'update' as const,
  message: 'Tap to update',
  action: () => {
    /* demo only */
  },
}

function openModal(size: ModalSize): void {
  openModalSize.value = size
}
</script>

<template>
  <div class="bg-surface-page text-ink min-h-screen">
    <div class="mx-auto max-w-[110rem] px-4 py-12 sm:px-6 lg:px-8">
      <PageHeader title="Design system" :icon="SwatchIcon">
        <template #subtitle>
          Every visual primitive in its meaningful states, and the named rules
          that govern how they compose. The gallery is the system made
          visible — anything that drifts here drifts in production.
        </template>
        <div class="text-meta flex flex-wrap items-center gap-x-4 gap-y-1">
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

      <GalleryTOCMobile :items="tocItems" />

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
            description="The smallest primitives — buttons, badges, avatars. Each block shows variants, sizes, and states, then the rule that governs how they compose."
          >
            <GallerySection
              id="atoms-buttons"
              title="Buttons"
              description="AppButton, TextButton, IconButton."
              motion="Press in, don't lift. Hover tints; active brightens by 5%. No translate, no scale, no bounce."
            >
              <SectionHeading :icon="Squares2X2Icon" title="Variants & sizes" />
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

                <GalleryRule
                  rule="One-Action Rule"
                  statement="Each card or modal carries at most one Primary button. Secondary actions are TextButtons or the secondary variant."
                  doc="https://github.com/iain/tayaway/blob/main/DESIGN.md#5-components"
                >
                  <div class="border-line bg-surface rounded-md border p-4">
                    <h5 class="text-ink font-semibold">Lock in dates</h5>
                    <p class="text-ink-muted text-sm">
                      The group has agreed on the 4th and 5th of October.
                      Confirm to send the calendar invite.
                    </p>
                    <div class="mt-4 flex items-center gap-3">
                      <AppButton variant="primary">Send invite</AppButton>
                      <TextButton variant="secondary">Edit dates</TextButton>
                    </div>
                  </div>
                </GalleryRule>

                <GalleryRule
                  rule="List-Row Rule"
                  statement="Repeated row actions are never Primary. Use secondary, inflow, or outflow so a stack of five rows doesn't read as five page-level CTAs."
                  doc="https://github.com/iain/tayaway/blob/main/DESIGN.md#5-components"
                >
                  <ul
                    class="border-line divide-line divide-y rounded-md border"
                  >
                    <li
                      v-for="row in [
                        { name: 'Daisy', amount: 24.5, action: 'inflow' as const, label: 'Mark received' },
                        { name: 'Iain', amount: 9.25, action: 'outflow' as const, label: 'Pay via QR' },
                        { name: 'Joep', amount: 18, action: 'inflow' as const, label: 'Mark received' },
                      ]"
                      :key="row.name"
                      class="bg-surface flex items-center gap-3 px-4 py-3"
                    >
                      <span class="text-ink text-label flex-1">{{
                        row.name
                      }}</span>
                      <LedgerAmount
                        :amount="row.amount"
                        :direction="row.action === 'inflow' ? 'in' : 'out'"
                      />
                      <AppButton :variant="row.action" size="sm">{{
                        row.label
                      }}</AppButton>
                    </li>
                  </ul>
                </GalleryRule>

                <GalleryRule
                  rule="Dual-Coding Rule"
                  statement="Where rows carry directional meaning, pair inflow with outflow so the colours echo the row's other signals."
                  doc="https://github.com/iain/tayaway/blob/main/DESIGN.md#5-components"
                >
                  <div class="flex flex-wrap items-center gap-2">
                    <AppButton variant="inflow" size="sm">+ Received</AppButton>
                    <AppButton variant="outflow" size="sm">− Pay</AppButton>
                  </div>
                </GalleryRule>
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

                <GalleryRule
                  rule="State, not decoration"
                  statement="A badge without a meaning is a violation. The API refuses colour-name variants; always say what the badge announces."
                  doc="https://github.com/iain/tayaway/blob/main/DESIGN.md#5-components"
                >
                  <div class="border-line bg-surface flex items-center gap-3 rounded-md border px-4 py-3">
                    <h5 class="text-ink text-label flex-1 font-semibold">
                      Lisbon weekend
                    </h5>
                    <AppBadge variant="pending">Voting</AppBadge>
                    <TimeAnchor :at="hoursAgoTs">Updated</TimeAnchor>
                  </div>
                </GalleryRule>
              </BaseCard>
            </GallerySection>
          </GalleryGroup>

          <GalleryGroup
            id="signatures"
            title="Signature primitives"
            description="The three signature moves: the amber landmark icon, the ledger amount, the time anchor — each carries the system's voice on its own."
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
              <SectionHeading :icon="ClockIcon" title="TimeAnchor" />
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

            <GallerySection
              id="signatures-daterange"
              title="Date ranges"
              description="One date when start equals end; a dash-joined range otherwise. Compact, locale-aware."
            >
              <SectionHeading :icon="CalendarIcon" title="DateRangeDisplay" />
              <BaseCard padded>
                <ul class="text-ink space-y-2">
                  <li>
                    <span class="text-ink-muted text-meta mr-2">Single day</span>
                    <DateRangeDisplay
                      :start-date="sameDayIso"
                      :end-date="sameDayIso"
                    />
                  </li>
                  <li>
                    <span class="text-ink-muted text-meta mr-2"
                      >Multi-day range</span
                    >
                    <DateRangeDisplay
                      :start-date="startIso"
                      :end-date="endIso"
                    />
                  </li>
                </ul>
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

            <GallerySection
              id="forms-currency"
              title="Currency input"
              description="A FormInput-shaped shell with a leading € glyph. Inputmode=decimal so mobile keyboards show the numeric pad."
            >
              <template #default="{ mode }">
                <SectionHeading :icon="BanknotesIcon" title="CurrencyInput" />
                <BaseCard padded>
                  <label
                    :for="`gallery-currency-${mode}`"
                    class="text-label text-ink mb-2 block"
                    >Amount paid</label
                  >
                  <CurrencyInput
                    :id="`gallery-currency-${mode}`"
                    v-model="currency"
                  />
                </BaseCard>
              </template>
            </GallerySection>

            <GallerySection
              id="forms-location"
              title="Location input"
              description="Photon-backed autocomplete behind a FormInput-shaped shell. The gallery renders it empty; live searches happen in the app."
            >
              <SectionHeading :icon="MapPinIcon" title="LocationInput" />
              <BaseCard padded>
                <LocationInput
                  v-model="location"
                  v-model:latitude="locationLat"
                  v-model:longitude="locationLng"
                  label="Where is the event?"
                />
              </BaseCard>
            </GallerySection>

            <GallerySection
              id="forms-composition"
              title="Form composition"
              description="FormSection wraps a heading + a grid of fields; FormActions caps the bottom with a cancel-then-submit row."
            >
              <template #default="{ mode }">
                <SectionHeading
                  :icon="ClipboardDocumentListIcon"
                  title="FormSection + FormActions"
                />
                <BaseCard padded>
                  <form @submit.prevent>
                    <FormSection
                      title="Trip details"
                      description="What the group is signing up for."
                    >
                      <div class="sm:col-span-4">
                        <FormInput
                          :id="`gallery-form-name-${mode}`"
                          v-model="composedText"
                          label="Event name"
                        />
                      </div>
                      <div class="sm:col-span-2">
                        <label
                          :for="`gallery-form-budget-${mode}`"
                          class="text-label text-ink mb-2 block"
                          >Budget per head</label
                        >
                        <CurrencyInput
                          :id="`gallery-form-budget-${mode}`"
                          v-model="composedCurrency"
                        />
                      </div>
                      <div class="sm:col-span-6">
                        <FormToggle
                          :id="`gallery-form-toggle-${mode}`"
                          v-model="composedToggle"
                          label="Send a calendar invite when dates are locked in"
                          description="Everyone in the group gets the event added to their calendar."
                        />
                      </div>
                    </FormSection>
                    <FormActions submit-label="Save event" />
                  </form>
                </BaseCard>
              </template>
            </GallerySection>
          </GalleryGroup>

          <GalleryGroup
            id="containers"
            title="Containers and surfaces"
            description="Cards, alerts, definition rows, and the empty-state pattern. Containers carry content; their job is to be calm."
          >
            <GallerySection
              id="containers-cards"
              title="Cards"
              description="Default, action, urgent, and the interactive variant. Hover lifts only the interactive one."
              motion="Interactive cards add a 2px ring on hover and a 5% brightness shift on active. Never scale or translate."
            >
              <SectionHeading :icon="RectangleStackIcon" title="Variants" />
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

              <BaseCard padded class="mt-4">
                <GalleryRule
                  rule="Quiet-Surface Rule"
                  statement="Cards stay in neutrals. Saturation belongs to actions and states. A card 'themed' with brand colour is a violation unless it's the action or urgent variant."
                  doc="https://github.com/iain/tayaway/blob/main/DESIGN.md#5-components"
                >
                  <div class="border-line bg-surface rounded-md border p-4">
                    <div class="mb-2 flex items-center justify-between">
                      <h5 class="text-ink font-semibold">
                        Settlement: Daisy ↔ Iain
                      </h5>
                      <AppBadge variant="success">Settled</AppBadge>
                    </div>
                    <p class="text-ink-muted text-sm">
                      Iain paid Daisy
                      <LedgerAmount :amount="9.25" direction="out" /> for
                      groceries.
                    </p>
                  </div>
                </GalleryRule>
              </BaseCard>
            </GallerySection>

            <GallerySection
              id="containers-alerts"
              title="Alerts"
              description="Banner-level messages for connection, sync, and confirmation. Errors interrupt; success and warning queue politely."
            >
              <SectionHeading
                :icon="ExclamationTriangleIcon"
                title="AlertBox"
              />
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
              <EmptyState
                :icon="CalendarDaysIcon"
                heading="No events yet"
                description="Create one to start coordinating with the group."
              >
                <AppButton>Plan an event</AppButton>
              </EmptyState>
            </GallerySection>

            <GallerySection
              id="containers-definition"
              title="Definition row"
              description="Read-and-edit list pattern. The whole row is the click target when editable; the inline pencil signals interactivity."
            >
              <SectionHeading
                :icon="IdentificationIcon"
                title="DefinitionRow"
              />
              <BaseCard padded>
                <dl class="divide-line divide-y">
                  <DefinitionRow label="Event name" edit-label="Edit name">
                    Lisbon weekend
                  </DefinitionRow>
                  <DefinitionRow label="Dates" edit-label="Edit dates">
                    <DateRangeDisplay
                      :start-date="startIso"
                      :end-date="endIso"
                    />
                  </DefinitionRow>
                  <DefinitionRow label="Budget per head">
                    <LedgerAmount :amount="250" />
                  </DefinitionRow>
                </dl>
              </BaseCard>
            </GallerySection>
          </GalleryGroup>

          <GalleryGroup
            id="landmarks"
            title="Region landmarks"
            description="PageHeader and SectionHeading carry the amber landmark icon — the system's most distinctive signature move."
          >
            <GallerySection
              id="landmarks-page"
              title="Page header"
              description="The H1 of a screen, plus an optional amber icon and subtitle. One per screen."
            >
              <SectionHeading :icon="BookmarkIcon" title="PageHeader anatomy" />
              <BaseCard padded>
                <PageHeader title="Lisbon weekend" :icon="CalendarDaysIcon">
                  <template #subtitle>
                    Three votes waiting. Decide on dates so the group can lock
                    in.
                  </template>
                  <AppButton variant="secondary">Edit trip</AppButton>
                </PageHeader>
                <div class="text-ink-muted text-meta -mt-2 ml-9 flex flex-wrap gap-x-4">
                  <span><span class="font-mono">text-page-title</span> · 30/700</span>
                  <span>icon <span class="font-mono">size-7</span> · <span class="font-mono">text-amber-600</span></span>
                  <span>subtitle <span class="font-mono">text-meta</span> · <span class="font-mono">text-ink-muted</span></span>
                </div>

                <GalleryRule
                  rule="Amber-Icon Rule"
                  statement="Amber landmark icons appear only on PageHeader (size-7), SectionHeading (size-5), and EmptyState (size-12). Nowhere else."
                  doc="https://github.com/iain/tayaway/blob/main/DESIGN.md#5-components"
                >
                  <p class="text-ink-muted text-sm">
                    The amber icon is how the system tells you "you're in a
                    new region." Reusing it on card titles, modal headers, or
                    button glyphs dilutes that signal.
                  </p>
                </GalleryRule>
              </BaseCard>
            </GallerySection>

            <GallerySection
              id="landmarks-section"
              title="Section heading"
              description="The H2 of a region. Same amber-icon vocabulary as PageHeader, one tier smaller."
            >
              <SectionHeading
                :icon="Bars3BottomLeftIcon"
                title="SectionHeading anatomy"
              />
              <BaseCard padded>
                <SectionHeading
                  :icon="CalendarDaysIcon"
                  title="Dates the group has agreed on"
                >
                  <TextButton>View all</TextButton>
                </SectionHeading>
                <div class="text-ink-muted text-meta -mt-2 ml-7 flex flex-wrap gap-x-4">
                  <span><span class="font-mono">text-section-heading</span> · 18/600</span>
                  <span>icon <span class="font-mono">size-5</span> · <span class="font-mono">text-amber-600</span></span>
                  <span>right slot · usually a <span class="font-mono">TextButton</span> or count</span>
                </div>
              </BaseCard>
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
              description="Native &lt;dialog&gt; with showModal(). The only place the system genuinely lifts. Five widths plus two reference compositions."
              motion="200ms cubic-bezier(0.25, 1, 0.5, 1) — fades, slides 8px up, scales from 0.98. prefers-reduced-motion collapses to 0.01ms."
            >
              <SectionHeading :icon="WindowIcon" title="BaseModal" />
              <BaseCard padded>
                <div class="space-y-4">
                  <div>
                    <p
                      class="text-ink-faint mb-2 text-xs tracking-wide uppercase"
                    >
                      Widths
                    </p>
                    <div class="flex flex-wrap items-center gap-2">
                      <AppButton
                        v-for="size in ['sm', 'md', 'lg', 'xl', '2xl'] as const"
                        :key="size"
                        variant="secondary"
                        size="sm"
                        @click="openModal(size)"
                        >Open {{ size }}</AppButton
                      >
                    </div>
                  </div>
                  <div>
                    <p
                      class="text-ink-faint mb-2 text-xs tracking-wide uppercase"
                    >
                      Compositions
                    </p>
                    <div class="flex flex-wrap items-center gap-2">
                      <AppButton @click="confirmOpen = true"
                        >Open modal</AppButton
                      >
                      <AppButton
                        variant="secondary"
                        @click="formModalOpen = true"
                        >Open form-in-modal</AppButton
                      >
                    </div>
                  </div>
                </div>
              </BaseCard>
            </GallerySection>

            <GallerySection
              id="overlays-toast"
              title="Toast"
              description="Transient notifications stacked top-right by the global ToastContainer. Info and error variants; an optional action link."
            >
              <SectionHeading :icon="MegaphoneIcon" title="ToastNotification" />
              <div class="space-y-3">
                <ToastNotification
                  :notification="toastInfo"
                  @dismiss="() => {}"
                />
                <ToastNotification
                  :notification="toastError"
                  @dismiss="() => {}"
                />
                <ToastNotification
                  :notification="toastAction"
                  @dismiss="() => {}"
                />
              </div>
            </GallerySection>

            <GallerySection
              id="overlays-updatepill"
              title="Update pill"
              description="Bottom-centre pill that prompts a one-tap PWA refresh when a new service worker is ready."
            >
              <SectionHeading :icon="ArrowPathIcon" title="UpdatePill" />
              <BaseCard padded>
                <p class="text-ink-muted text-sm mb-3">
                  Live render uses <span class="font-mono">position: fixed</span>;
                  shown here in flow so the gallery layout stays legible.
                </p>
                <div class="flex justify-center">
                  <button
                    type="button"
                    class="flex items-center gap-2 rounded-full bg-amber-600 px-4 py-2 text-sm font-medium text-white shadow-lg dark:bg-amber-700"
                  >
                    <ArrowPathIcon class="size-4" aria-hidden="true" />
                    {{ updatePill.message }}
                  </button>
                </div>
              </BaseCard>
            </GallerySection>
          </GalleryGroup>

          <section class="border-line border-t pt-6">
            <p class="text-ink-faint text-meta">
              <span class="text-ink font-medium">Not in gallery:</span>
              CommandPalette, NotificationBell, and StaticMap render only
              inside the app shell — they bind to live stores or load Leaflet
              over the network. Their coverage lives in feature tests, not on
              this page.
            </p>
          </section>
        </div>
      </div>
    </div>

    <BaseModal
      v-for="size in (['sm', 'md', 'lg', 'xl', '2xl'] as const)"
      :key="size"
      :open="openModalSize === size"
      :size="size"
      :title="`Modal width — ${size}`"
      @close="openModalSize = null"
    >
      <p class="text-ink-muted text-sm">
        The {{ size }} width sits at
        <span class="font-mono">sm:max-w-{{ size }}</span> on viewports above
        640px and grows to the viewport width below.
      </p>
    </BaseModal>

    <BaseModal
      :open="confirmOpen"
      title="Confirm delete"
      @close="confirmOpen = false"
    >
      <p class="text-ink-muted">
        This will remove the event for everyone in the group. This can't be
        undone.
      </p>
      <div class="mt-6 flex justify-end gap-2">
        <AppButton variant="secondary" @click="confirmOpen = false"
          >Cancel</AppButton
        >
        <AppButton variant="danger" @click="confirmOpen = false"
          >Delete</AppButton
        >
      </div>
    </BaseModal>

    <BaseModal
      :open="formModalOpen"
      size="lg"
      title="Plan an event"
      @close="formModalOpen = false"
    >
      <form @submit.prevent="formModalOpen = false">
        <FormInput
          id="gallery-modal-name"
          v-model="modalText"
          label="Event name"
          placeholder="e.g. Lisbon weekend"
        />
        <FormActions
          submit-label="Create event"
          @cancel="formModalOpen = false"
        />
      </form>
    </BaseModal>
  </div>
</template>
