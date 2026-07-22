<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import {
  ArrowPathIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  DocumentMagnifyingGlassIcon,
  LockClosedIcon,
} from '@heroicons/vue/24/outline'
import { rawApi } from '@/api/client'
import { useWorkspaceStore } from '@/stores/workspace'
import { useObjectPoolStore } from '@/stores/objectPool'
import { can } from '@/composables/usePermission'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseCard from '@/components/common/BaseCard.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import AppBadge from '@/components/common/AppBadge.vue'
import AppButton from '@/components/common/AppButton.vue'
import TimeAnchor from '@/components/common/TimeAnchor.vue'
import type { AuditLogEntry, AuditLogPage } from '@/types/auditLog'
import type { ObjectType } from '@/types/pool'

const workspaceStore = useWorkspaceStore()
const pool = useObjectPoolStore()

const canView = computed(() =>
  can(workspaceStore.currentWorkspace?.permissions, 'view_audit_log')
)

const entries = ref<AuditLogEntry[]>([])
const nextCursor = ref<string | null>(null)
// Cursors of the pages we descended through; cursorTrail[i] fetches page
// i + 2 (page 1 needs no cursor). "Newer" pops, "Older" pushes.
const cursorTrail = ref<string[]>([])
const pageNumber = computed(() => cursorTrail.value.length + 1)
const isLoading = ref(false)
const loadFailed = ref(false)
const expandedId = ref<string | null>(null)

async function fetchPage(cursor: string | null): Promise<void> {
  const wsId = workspaceStore.currentWorkspaceId
  if (!wsId) return
  isLoading.value = true
  loadFailed.value = false
  expandedId.value = null
  try {
    const query = cursor ? `?cursor=${encodeURIComponent(cursor)}` : ''
    const response = await rawApi.get<AuditLogPage>(
      `/workspaces/${wsId}/audit-log${query}`
    )
    // A workspace switch mid-flight makes this response stale — drop it.
    if (workspaceStore.currentWorkspaceId !== wsId) return
    entries.value = response.data.entries
    nextCursor.value = response.data.nextCursor
  } catch {
    loadFailed.value = true
  } finally {
    isLoading.value = false
  }
}

function refresh(): void {
  cursorTrail.value = []
  void fetchPage(null)
}

function goOlder(): void {
  if (!nextCursor.value || isLoading.value) return
  cursorTrail.value.push(nextCursor.value)
  void fetchPage(nextCursor.value)
}

function goNewer(): void {
  if (cursorTrail.value.length === 0 || isLoading.value) return
  cursorTrail.value.pop()
  void fetchPage(cursorTrail.value.at(-1) ?? null)
}

watch(
  () => [workspaceStore.currentWorkspaceId, canView.value] as const,
  ([wsId, allowed]) => {
    entries.value = []
    nextCursor.value = null
    cursorTrail.value = []
    if (wsId && allowed) refresh()
  },
  { immediate: true }
)

function toggleExpanded(id: string): void {
  expandedId.value = expandedId.value === id ? null : id
}

// "ChoreRosters::CreateAssignment" → action "Create assignment", domain
// "Chore rosters". The raw service string stays visible in the detail view.
function serviceParts(service: string): { action: string; domain: string } {
  const [domain = '', verb = ''] = service.split('::')
  const spaced = (s: string) =>
    s.replace(/([a-z])([A-Z])/g, '$1 $2').toLowerCase()
  const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)
  if (!verb) return { action: service, domain: '' }
  return {
    action: capitalize(spaced(verb)),
    domain: capitalize(spaced(domain)),
  }
}

// Audit rows store snake_case subject types; the pool uses client types.
// Used to look up a display name for subjects that still exist locally.
const SUBJECT_POOL_TYPE: Record<string, ObjectType> = {
  event: 'event',
  workspace_membership: 'member',
  workspace_invite: 'workspaceInvite',
  chore: 'chore',
  chore_roster: 'choreRoster',
  chore_assignment: 'choreAssignment',
  date_poll: 'datePoll',
  date_range: 'dateRange',
  expense: 'expense',
  settlement: 'settlement',
  settlement_transfer: 'settlementTransfer',
  task_item: 'taskItem',
  task_list: 'taskList',
  vote: 'vote',
}

function subjectName(entry: AuditLogEntry): string | null {
  if (!entry.subjectType || !entry.subjectId) return null
  const poolType = SUBJECT_POOL_TYPE[entry.subjectType]
  if (!poolType) return null
  const obj = pool.get(poolType, entry.subjectId) as
    { name?: string; description?: string } | undefined
  return obj?.name ?? null
}

function subjectTypeLabel(entry: AuditLogEntry): string | null {
  if (!entry.subjectType) return null
  return entry.subjectType.replace(/_/g, ' ')
}

function actorLabel(entry: AuditLogEntry): string {
  if (entry.actorKind === 'system') return 'System'
  return entry.actorName ?? 'Deleted user'
}

const OUTCOME_VARIANTS = {
  success: 'success',
  denied: 'danger',
  error: 'warning',
} as const

function hasParams(entry: AuditLogEntry): boolean {
  return Object.keys(entry.actionParams).length > 0
}

function formatParams(entry: AuditLogEntry): string {
  return JSON.stringify(entry.actionParams, null, 2)
}
</script>

<template>
  <div>
    <PageHeader
      title="Audit log"
      :icon="DocumentMagnifyingGlassIcon"
      data-testid="page-title"
    >
      <AppButton
        v-if="canView"
        variant="secondary"
        :disabled="isLoading"
        data-testid="audit-log-refresh"
        @click="refresh"
      >
        <ArrowPathIcon class="size-5" :class="{ 'animate-spin': isLoading }" />
        Refresh
      </AppButton>
    </PageHeader>

    <!-- The backend enforces this too; the empty state covers deep links
         and the window between load and role changes. -->
    <EmptyState
      v-if="workspaceStore.currentWorkspace && !canView"
      :icon="LockClosedIcon"
      heading="Owner only"
      description="Only the workspace owner can view the audit log."
      data-testid="audit-log-forbidden"
    />

    <template v-else>
      <div
        v-if="loadFailed"
        class="py-12 text-center"
        data-testid="audit-log-error"
      >
        <p class="text-ink-muted text-base">Could not load the audit log.</p>
        <AppButton
          class="mt-4"
          variant="secondary"
          @click="fetchPage(cursorTrail.at(-1) ?? null)"
        >
          Try again
        </AppButton>
      </div>

      <div
        v-else-if="isLoading && entries.length === 0"
        class="flex justify-center py-12"
        data-testid="audit-log-loading"
      >
        <div
          class="inline-block size-8 animate-spin rounded-full border-4 border-amber-600 border-t-transparent"
        />
      </div>

      <EmptyState
        v-else-if="entries.length === 0"
        :icon="DocumentMagnifyingGlassIcon"
        heading="No activity yet"
        description="Actions taken in this workspace will show up here."
      />

      <template v-else>
        <BaseCard
          as="ul"
          class="divide-line divide-y"
          data-testid="audit-log-list"
        >
          <li v-for="entry in entries" :key="entry.id">
            <button
              type="button"
              class="focus-visible:outline-focus hover:bg-btn-secondary-fill/50 flex w-full cursor-pointer flex-wrap items-center gap-x-3 gap-y-1 px-4 py-3 text-left focus-visible:outline-2 focus-visible:-outline-offset-2 sm:px-6"
              :data-testid="`audit-log-entry-${entry.id}`"
              :aria-expanded="expandedId === entry.id"
              @click="toggleExpanded(entry.id)"
            >
              <span
                class="text-ink min-w-0 flex-1 truncate text-sm font-medium"
              >
                {{ serviceParts(entry.service).action }}
                <span
                  v-if="serviceParts(entry.service).domain"
                  class="text-ink-muted font-normal"
                >
                  · {{ serviceParts(entry.service).domain }}
                </span>
              </span>
              <span
                v-if="subjectTypeLabel(entry)"
                class="text-ink-muted hidden max-w-48 truncate text-sm sm:inline"
                data-testid="audit-log-subject"
              >
                {{ subjectName(entry) ?? subjectTypeLabel(entry) }}
              </span>
              <AppBadge :variant="OUTCOME_VARIANTS[entry.outcome]">
                {{ entry.outcome }}
              </AppBadge>
              <span
                class="text-ink-muted w-40 shrink-0 truncate text-right text-xs"
              >
                {{ actorLabel(entry) }}
                ·
                <TimeAnchor :at="entry.createdAt" />
              </span>
            </button>

            <div
              v-if="expandedId === entry.id"
              class="bg-surface-page/50 border-line border-t px-4 py-4 sm:px-6"
              :data-testid="`audit-log-detail-${entry.id}`"
            >
              <dl
                class="grid grid-cols-1 gap-x-6 gap-y-3 text-sm sm:grid-cols-2"
              >
                <div>
                  <dt class="text-ink-muted text-xs font-semibold uppercase">
                    Service
                  </dt>
                  <dd class="text-ink mt-0.5 font-mono text-xs">
                    {{ entry.service }}
                  </dd>
                </div>
                <div>
                  <dt class="text-ink-muted text-xs font-semibold uppercase">
                    Time
                  </dt>
                  <dd class="text-ink mt-0.5 font-mono text-xs">
                    {{ entry.createdAt }}
                  </dd>
                </div>
                <div>
                  <dt class="text-ink-muted text-xs font-semibold uppercase">
                    Actor
                  </dt>
                  <dd class="text-ink mt-0.5">
                    {{ actorLabel(entry) }}
                    <span
                      v-if="entry.actorUserId"
                      class="text-ink-muted font-mono text-xs"
                    >
                      ({{ entry.actorUserId }})
                    </span>
                  </dd>
                </div>
                <div v-if="entry.subjectType">
                  <dt class="text-ink-muted text-xs font-semibold uppercase">
                    Subject
                  </dt>
                  <dd class="text-ink mt-0.5">
                    {{ subjectTypeLabel(entry) }}
                    <span
                      v-if="entry.subjectId"
                      class="text-ink-muted font-mono text-xs"
                    >
                      ({{ entry.subjectId }})
                    </span>
                  </dd>
                </div>
                <div v-if="entry.errorCode || entry.outcome !== 'success'">
                  <dt class="text-ink-muted text-xs font-semibold uppercase">
                    Outcome
                  </dt>
                  <dd class="text-ink mt-0.5">
                    {{ entry.outcome }}
                    <span v-if="entry.errorCode" class="font-mono text-xs">
                      ({{ entry.errorCode }})
                    </span>
                  </dd>
                </div>
                <div v-if="entry.requestId">
                  <dt class="text-ink-muted text-xs font-semibold uppercase">
                    Request ID
                  </dt>
                  <dd class="text-ink mt-0.5 font-mono text-xs">
                    {{ entry.requestId }}
                  </dd>
                </div>
                <div v-if="entry.idempotencyKeyHash">
                  <dt class="text-ink-muted text-xs font-semibold uppercase">
                    Idempotency key
                  </dt>
                  <dd class="text-ink mt-0.5 truncate font-mono text-xs">
                    {{ entry.idempotencyKeyHash }}
                  </dd>
                </div>
              </dl>

              <div v-if="entry.errorMessage" class="mt-3">
                <dt class="text-ink-muted text-xs font-semibold uppercase">
                  Error
                </dt>
                <p
                  class="text-state-danger-ink bg-state-danger-fill mt-1 rounded-md px-3 py-2 text-sm"
                >
                  {{ entry.errorMessage }}
                </p>
              </div>

              <div v-if="hasParams(entry)" class="mt-3">
                <dt class="text-ink-muted text-xs font-semibold uppercase">
                  Parameters
                </dt>
                <pre
                  class="text-ink bg-surface border-line mt-1 overflow-x-auto rounded-md border px-3 py-2 font-mono text-xs"
                  data-testid="audit-log-params"
                  >{{ formatParams(entry) }}</pre>
              </div>
            </div>
          </li>
        </BaseCard>

        <div
          class="mt-4 flex items-center justify-between"
          data-testid="audit-log-pagination"
        >
          <AppButton
            variant="secondary"
            size="sm"
            :disabled="pageNumber === 1 || isLoading"
            data-testid="audit-log-newer"
            @click="goNewer"
          >
            <ChevronLeftIcon class="size-4" />
            Newer
          </AppButton>
          <span class="text-ink-muted text-sm">Page {{ pageNumber }}</span>
          <AppButton
            variant="secondary"
            size="sm"
            :disabled="!nextCursor || isLoading"
            data-testid="audit-log-older"
            @click="goOlder"
          >
            Older
            <ChevronRightIcon class="size-4" />
          </AppButton>
        </div>
      </template>
    </template>
  </div>
</template>
