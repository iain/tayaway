<script setup lang="ts">
import { computed, ref } from 'vue'
import {
  BanknotesIcon,
  ChevronDownIcon,
  QrCodeIcon,
} from '@heroicons/vue/24/outline'
import { storeToRefs } from 'pinia'
import {
  useAuthStore,
  useObjectPoolStore,
  useSettlementsStore,
  useWebSocketStore,
  useWorkspaceStore,
} from '@/stores'
import {
  useWorkspaceNet,
  type NetSettlement,
  type RecentSettlement,
} from '@/composables/useWorkspaceNet'
import { getMemberName } from '@/utils/member'
import { formatAmount } from '@/utils/format'
import { formatRelativeDate } from '@/utils/date'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import AlertBox from '@/components/common/AlertBox.vue'
import EpcQrModal from '@/components/expenses/EpcQrModal.vue'
import { CheckCircleIcon } from '@heroicons/vue/24/solid'

const pool = useObjectPoolStore()
const auth = useAuthStore()
const workspace = useWorkspaceStore()
const ws = useWebSocketStore()
const settlementsStore = useSettlementsStore()
const { user } = storeToRefs(auth)
const { hasSynced } = storeToRefs(ws)

const { netSettlements, recentSettlements } = useWorkspaceNet()

const owedToYou = computed(() =>
  netSettlements.value.filter((s) => s.direction === 'owed')
)
const youOwe = computed(() =>
  netSettlements.value.filter((s) => s.direction === 'owe')
)

// Single-expand: opening one card collapses any other. Cuts the cognitive
// load of comparing two breakdowns at once and avoids the Set-mutation
// reactivity dance.
const expandedId = ref<string | null>(null)
function isExpanded(id: string): boolean {
  return expandedId.value === id
}
function toggleExpanded(id: string) {
  expandedId.value = expandedId.value === id ? null : id
}

const markingIds = ref<Set<string>>(new Set())
async function handleMarkPaid(net: NetSettlement) {
  const workspaceId = workspace.currentWorkspaceId
  if (!workspaceId || markingIds.value.has(net.id)) return
  markingIds.value.add(net.id)
  markingIds.value = new Set(markingIds.value)
  try {
    await settlementsStore.markNetPaid({
      workspaceId,
      counterpartyUserId: net.counterpartyUserId,
      expectedAmount: net.amount,
      underlyingTransferIds: net.underlyingTransferIds,
    })
  } finally {
    markingIds.value.delete(net.id)
    markingIds.value = new Set(markingIds.value)
  }
}

const qrOpen = ref(false)
const qrNetRequest = ref<{
  workspaceId: string
  counterpartyUserId: string
  expectedAmount: number
  underlyingTransferIds: string[]
} | null>(null)
const qrRecipientName = ref<string | null>(null)
const qrAmount = ref<number | null>(null)

function openQr(net: NetSettlement) {
  const workspaceId = workspace.currentWorkspaceId
  if (!workspaceId) return
  qrNetRequest.value = {
    workspaceId,
    counterpartyUserId: net.counterpartyUserId,
    expectedAmount: net.amount,
    underlyingTransferIds: net.underlyingTransferIds,
  }
  qrRecipientName.value = getMemberName(net.counterpartyUserId, pool)
  qrAmount.value = net.amount
  qrOpen.value = true
}

function eventNameFor(eventId: string | undefined): string {
  if (!eventId) return 'Unknown event'
  return pool.get('event', eventId)?.name ?? 'Unknown event'
}

function breakdownAria(amount: number, dominant: boolean): string {
  // Mirrors the +/− glyph for screen readers — they get the meaning
  // ("adds" vs "offsets") without having to interpret a sign.
  const verb = dominant ? 'adds' : 'offsets'
  return `${verb} ${formatAmount(amount)}`
}

function settledByLabel(net: RecentSettlement): string {
  const viewerId = auth.currentUserId
  if (!net.paidByUserId) return ''
  if (net.paidByUserId === viewerId) return 'Marked by you'
  return `Marked by ${getMemberName(net.paidByUserId, pool)}`
}

const unmarkingIds = ref<Set<string>>(new Set())
async function handleUnmark(net: RecentSettlement) {
  const workspaceId = workspace.currentWorkspaceId
  if (!workspaceId || unmarkingIds.value.has(net.id)) return
  unmarkingIds.value.add(net.id)
  unmarkingIds.value = new Set(unmarkingIds.value)
  try {
    await settlementsStore.markNetUnpaid({
      workspaceId,
      counterpartyUserId: net.counterpartyUserId,
      underlyingTransferIds: net.underlyingTransferIds,
    })
  } finally {
    unmarkingIds.value.delete(net.id)
    unmarkingIds.value = new Set(unmarkingIds.value)
  }
}
</script>

<template>
  <div>
    <PageHeader title="Settle up" data-testid="page-title">
      <template #subtitle>
        Net balances across every event in this workspace, so you only transfer
        what's actually owed.
      </template>
    </PageHeader>

    <AlertBox
      v-if="owedToYou.length > 0 && !user?.iban"
      variant="warning"
      :icon="BanknotesIcon"
      class="mb-6"
    >
      <p class="text-sm">
        Add your IBAN so others can pay you with a single QR code scan.
      </p>
      <router-link
        to="/profile"
        class="mt-1 inline-block text-sm font-medium text-amber-700 underline hover:text-amber-900 dark:text-amber-400 dark:hover:text-amber-200"
      >
        Add IBAN in profile
      </router-link>
    </AlertBox>

    <div
      v-if="
        !hasSynced &&
        netSettlements.length === 0 &&
        recentSettlements.length === 0
      "
      class="space-y-3"
      data-testid="settle-up-loading"
      aria-busy="true"
      aria-live="polite"
    >
      <span class="sr-only">Loading your balances</span>
      <div
        v-for="i in 2"
        :key="i"
        class="h-20 animate-pulse rounded-lg bg-gray-100 dark:bg-stone-800"
      />
    </div>

    <div
      v-else-if="netSettlements.length === 0 && recentSettlements.length === 0"
      class="py-16 text-center"
      data-testid="settle-up-empty"
    >
      <CheckCircleIcon
        class="mx-auto size-16 text-amber-500 dark:text-amber-400"
        aria-hidden="true"
      />
      <h2 class="mt-4 text-xl font-semibold text-gray-900 dark:text-white">
        You're all square.
      </h2>
      <p class="mt-2 text-sm text-gray-500 dark:text-stone-400">
        Nothing to settle right now — come back after the next event.
      </p>
    </div>

    <div
      v-else-if="netSettlements.length > 0 || recentSettlements.length > 0"
      class="flex flex-col gap-8"
    >
      <section v-if="owedToYou.length > 0">
        <h2 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
          Owed to you
        </h2>
        <ul class="space-y-3">
          <BaseCard
            v-for="net in owedToYou"
            :key="net.id"
            as="li"
            class="overflow-hidden"
          >
            <div
              class="flex flex-wrap items-center justify-between gap-y-2 px-4 py-3 sm:px-6"
            >
              <div class="min-w-0 flex-1">
                <p class="text-sm text-gray-900 dark:text-white">
                  <span class="font-semibold">{{
                    getMemberName(net.counterpartyUserId, pool)
                  }}</span>
                  owes you
                  <span
                    class="font-mono font-semibold text-gray-900 dark:text-white"
                    >{{ formatAmount(net.amount) }}</span
                  >
                </p>
                <button
                  type="button"
                  class="mt-0.5 inline-flex items-center gap-1 text-xs text-gray-500 hover:text-rose-600 dark:text-stone-400 dark:hover:text-rose-400"
                  :aria-expanded="isExpanded(net.id)"
                  @click="toggleExpanded(net.id)"
                >
                  <span>
                    {{ net.transferCount }}
                    {{ net.transferCount === 1 ? 'transfer' : 'transfers' }}
                    across
                    {{ net.eventCount }}
                    {{ net.eventCount === 1 ? 'event' : 'events' }}
                  </span>
                  <ChevronDownIcon
                    class="size-3 transition-transform"
                    :class="{ 'rotate-180': isExpanded(net.id) }"
                    aria-hidden="true"
                  />
                </button>
              </div>
              <button
                type="button"
                :disabled="markingIds.has(net.id)"
                class="cursor-pointer rounded-md bg-cyan-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-cyan-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-cyan-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-cyan-700 dark:hover:bg-cyan-600"
                @click="handleMarkPaid(net)"
              >
                {{ markingIds.has(net.id) ? 'Marking...' : 'Mark as received' }}
              </button>
            </div>
            <div
              v-if="isExpanded(net.id)"
              class="border-t border-gray-100 bg-gray-50 px-4 py-3 sm:px-6 dark:border-stone-700 dark:bg-stone-900/50"
            >
              <ul class="space-y-1 text-xs">
                <li
                  v-for="b in net.breakdown"
                  :key="b.transfer.id"
                  class="flex items-center justify-between gap-3"
                >
                  <router-link
                    v-if="b.event?.id"
                    :to="`/events/${b.event.id}/expenses`"
                    class="truncate text-gray-700 hover:text-rose-600 hover:underline dark:text-stone-300 dark:hover:text-rose-400"
                  >
                    {{ eventNameFor(b.event?.id) }}
                  </router-link>
                  <span
                    v-else
                    class="truncate text-gray-700 dark:text-stone-300"
                  >
                    {{ eventNameFor(b.event?.id) }}
                  </span>
                  <span
                    class="shrink-0 font-mono"
                    :class="
                      b.isDominantDirection
                        ? 'text-cyan-700 dark:text-cyan-300'
                        : 'text-amber-700 dark:text-amber-400'
                    "
                  >
                    <span aria-hidden="true">
                      {{ b.isDominantDirection ? '+' : '−'
                      }}{{ formatAmount(b.transfer.amount) }}
                    </span>
                    <span class="sr-only">
                      {{
                        breakdownAria(b.transfer.amount, b.isDominantDirection)
                      }}
                    </span>
                  </span>
                </li>
              </ul>
              <p
                class="mt-2 text-[11px] tracking-wide text-gray-400 dark:text-stone-500"
                aria-hidden="true"
              >
                + adds to the net · − offsets it
              </p>
            </div>
          </BaseCard>
        </ul>
      </section>

      <section v-if="youOwe.length > 0">
        <h2 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
          You owe
        </h2>
        <ul class="space-y-3">
          <BaseCard
            v-for="net in youOwe"
            :key="net.id"
            as="li"
            variant="action"
            class="overflow-hidden"
          >
            <div
              class="flex flex-wrap items-center justify-between gap-y-2 px-4 py-3 sm:px-6"
            >
              <div class="min-w-0 flex-1">
                <p class="text-sm text-gray-700 dark:text-stone-300">
                  You owe
                  <span class="font-semibold text-gray-900 dark:text-white">{{
                    getMemberName(net.counterpartyUserId, pool)
                  }}</span>
                </p>
                <p
                  class="mt-0.5 font-mono text-lg font-bold text-amber-700 dark:text-amber-400"
                >
                  {{ formatAmount(net.amount) }}
                </p>
                <button
                  type="button"
                  class="mt-0.5 inline-flex items-center gap-1 text-xs text-gray-500 hover:text-rose-600 dark:text-stone-400 dark:hover:text-rose-400"
                  :aria-expanded="isExpanded(net.id)"
                  @click="toggleExpanded(net.id)"
                >
                  <span>
                    {{ net.transferCount }}
                    {{ net.transferCount === 1 ? 'transfer' : 'transfers' }}
                    across
                    {{ net.eventCount }}
                    {{ net.eventCount === 1 ? 'event' : 'events' }}
                  </span>
                  <ChevronDownIcon
                    class="size-3 transition-transform"
                    :class="{ 'rotate-180': isExpanded(net.id) }"
                    aria-hidden="true"
                  />
                </button>
              </div>
              <button
                type="button"
                class="inline-flex cursor-pointer items-center gap-1.5 rounded-md bg-amber-600 px-3 py-1.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-500 dark:bg-amber-600 dark:hover:bg-amber-500"
                title="Show QR code for bank transfer"
                @click="openQr(net)"
              >
                <QrCodeIcon class="size-4" aria-hidden="true" />
                Pay via QR
              </button>
            </div>
            <div
              v-if="isExpanded(net.id)"
              class="border-t border-amber-200/60 bg-amber-50/40 px-4 py-3 sm:px-6 dark:border-amber-800/40 dark:bg-amber-950/20"
            >
              <ul class="space-y-1 text-xs">
                <li
                  v-for="b in net.breakdown"
                  :key="b.transfer.id"
                  class="flex items-center justify-between gap-3"
                >
                  <router-link
                    v-if="b.event?.id"
                    :to="`/events/${b.event.id}/expenses`"
                    class="truncate text-gray-700 hover:text-rose-600 hover:underline dark:text-stone-300 dark:hover:text-rose-400"
                  >
                    {{ eventNameFor(b.event?.id) }}
                  </router-link>
                  <span
                    v-else
                    class="truncate text-gray-700 dark:text-stone-300"
                  >
                    {{ eventNameFor(b.event?.id) }}
                  </span>
                  <span
                    class="shrink-0 font-mono"
                    :class="
                      b.isDominantDirection
                        ? 'text-amber-700 dark:text-amber-400'
                        : 'text-cyan-700 dark:text-cyan-300'
                    "
                  >
                    <span aria-hidden="true">
                      {{ b.isDominantDirection ? '+' : '−'
                      }}{{ formatAmount(b.transfer.amount) }}
                    </span>
                    <span class="sr-only">
                      {{
                        breakdownAria(b.transfer.amount, b.isDominantDirection)
                      }}
                    </span>
                  </span>
                </li>
              </ul>
              <p
                class="mt-2 text-[11px] tracking-wide text-gray-400 dark:text-stone-500"
                aria-hidden="true"
              >
                + adds to the net · − offsets it
              </p>
            </div>
          </BaseCard>
        </ul>
      </section>

      <section v-if="recentSettlements.length > 0" data-testid="recent-settled">
        <h2 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
          Recently settled
        </h2>
        <ul class="space-y-3">
          <BaseCard
            v-for="net in recentSettlements"
            :key="net.id"
            as="li"
            class="overflow-hidden opacity-90"
          >
            <div
              class="flex flex-wrap items-center justify-between gap-y-2 px-4 py-3 sm:px-6"
            >
              <div class="min-w-0 flex-1">
                <p class="text-sm text-gray-700 dark:text-stone-300">
                  <template v-if="net.direction === 'paid'">
                    You paid
                    <span class="font-semibold text-gray-900 dark:text-white">{{
                      getMemberName(net.counterpartyUserId, pool)
                    }}</span>
                  </template>
                  <template v-else>
                    <span class="font-semibold text-gray-900 dark:text-white">{{
                      getMemberName(net.counterpartyUserId, pool)
                    }}</span>
                    paid you
                  </template>
                </p>
                <p
                  class="mt-0.5 font-mono text-lg font-semibold text-gray-700 dark:text-stone-300"
                >
                  {{ formatAmount(net.amount) }}
                </p>
                <p class="mt-0.5 text-xs text-gray-500 dark:text-stone-400">
                  {{ formatRelativeDate(net.latestPaidAt) }}
                  <template v-if="settledByLabel(net)">
                    · {{ settledByLabel(net) }}
                  </template>
                </p>
                <button
                  type="button"
                  class="mt-0.5 inline-flex items-center gap-1 text-xs text-gray-500 hover:text-rose-600 dark:text-stone-400 dark:hover:text-rose-400"
                  :aria-expanded="isExpanded(net.id)"
                  @click="toggleExpanded(net.id)"
                >
                  <span>
                    {{ net.transferCount }}
                    {{ net.transferCount === 1 ? 'transfer' : 'transfers' }}
                    across
                    {{ net.eventCount }}
                    {{ net.eventCount === 1 ? 'event' : 'events' }}
                  </span>
                  <ChevronDownIcon
                    class="size-3 transition-transform"
                    :class="{ 'rotate-180': isExpanded(net.id) }"
                    aria-hidden="true"
                  />
                </button>
              </div>
              <button
                type="button"
                :disabled="unmarkingIds.has(net.id)"
                class="cursor-pointer rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm transition-colors hover:bg-gray-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-600 disabled:cursor-not-allowed disabled:opacity-50 dark:border-stone-600 dark:bg-stone-800 dark:text-stone-200 dark:hover:bg-stone-700"
                @click="handleUnmark(net)"
              >
                {{ unmarkingIds.has(net.id) ? 'Unmarking…' : 'Unmark' }}
              </button>
            </div>
            <div
              v-if="isExpanded(net.id)"
              class="border-t border-gray-100 bg-gray-50 px-4 py-3 sm:px-6 dark:border-stone-700 dark:bg-stone-900/50"
            >
              <ul class="space-y-1 text-xs">
                <li
                  v-for="b in net.breakdown"
                  :key="b.transfer.id"
                  class="flex items-center justify-between gap-3"
                >
                  <router-link
                    v-if="b.event?.id"
                    :to="`/events/${b.event.id}/expenses`"
                    class="truncate text-gray-700 hover:text-rose-600 hover:underline dark:text-stone-300 dark:hover:text-rose-400"
                  >
                    {{ eventNameFor(b.event?.id) }}
                  </router-link>
                  <span
                    v-else
                    class="truncate text-gray-700 dark:text-stone-300"
                  >
                    {{ eventNameFor(b.event?.id) }}
                  </span>
                  <span
                    class="shrink-0 font-mono"
                    :class="
                      b.isDominantDirection
                        ? 'text-gray-700 dark:text-stone-300'
                        : 'text-gray-400 dark:text-stone-500'
                    "
                  >
                    <span aria-hidden="true">
                      {{ b.isDominantDirection ? '+' : '−'
                      }}{{ formatAmount(b.transfer.amount) }}
                    </span>
                    <span class="sr-only">
                      {{
                        breakdownAria(b.transfer.amount, b.isDominantDirection)
                      }}
                    </span>
                  </span>
                </li>
              </ul>
              <p
                class="mt-2 text-[11px] tracking-wide text-gray-400 dark:text-stone-500"
                aria-hidden="true"
              >
                + adds to the net · − offsets it
              </p>
            </div>
          </BaseCard>
        </ul>
      </section>
    </div>

    <EpcQrModal
      :open="qrOpen"
      :net-request="qrNetRequest"
      :recipient-name="qrRecipientName"
      :amount="qrAmount"
      @close="qrOpen = false"
    />
  </div>
</template>
