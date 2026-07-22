<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Menu, MenuButton, MenuItem, MenuItems } from '@headlessui/vue'
import { CalendarDaysIcon, ChevronDownIcon } from '@heroicons/vue/24/outline'
import { eventHasDates } from '@/utils/event'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import { useFocusedEvent } from '@/composables/useFocusedEvent'
import type { PoolEvent } from '@/types/pool'

const props = defineProps<{
  event: PoolEvent
}>()

const route = useRoute()

// The bar outlives the event routes — it also heads workspace pages while an
// event holds focus — so links hang off the event it was handed, not the URL.
const eventId = computed(() => props.event.id)

const activeTab = computed(() => {
  const name = route.name as string
  if (
    name === 'event-planning' ||
    name === 'event-planning-vote' ||
    name === 'event-planning-date-ranges'
  )
    return 'planning'
  if (name === 'event-rsvp') return 'rsvp'
  if (name === 'event-days') return 'days'
  if (name === 'event-expenses') return 'expenses'
  if (name === 'event-chores') return 'chores'
  return null
})

const router = useRouter()
const { focusCandidates, pinEvent } = useFocusedEvent()

const otherEvents = computed(() =>
  focusCandidates.value.filter((e) => e.id !== props.event.id)
)

// Switching focus keeps you where you are: on an event page you land on the
// same tab of the event you picked, and on a workspace page (chores, settle
// up) the page simply re-renders for the new focus.
async function switchTo(eventId: string): Promise<void> {
  pinEvent(eventId)
  const name = route.name as string
  if (typeof name === 'string' && name.startsWith('event')) {
    await router.push({ name, params: { ...route.params, id: eventId } })
  }
}

function tabClass(active: boolean): string {
  return [
    'shrink-0 rounded-md px-3 py-1.5 text-sm font-medium whitespace-nowrap transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus',
    active
      ? 'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300'
      : 'text-ink-muted hover:bg-surface-page hover:text-ink',
  ].join(' ')
}
</script>

<template>
  <!-- Event subheader: name, dates, and tab navigation -->
  <div class="border-line bg-surface border-b">
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div
        class="flex flex-col py-3 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="min-w-0">
          <p class="text-ink-muted text-xs font-medium tracking-wide uppercase">
            Event
          </p>
          <!-- Positioned here rather than on the Menu so the dropdown hangs
               off the row's left edge: anchored to the trigger it would start
               wherever the (truncated, variable-length) name happens to end,
               and run off a narrow screen. -->
          <div class="relative flex items-center gap-2">
            <router-link
              :to="`/events/${eventId}`"
              data-testid="event-name"
              class="text-ink focus-visible:outline-focus block truncate rounded text-lg font-semibold hover:text-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 dark:hover:text-amber-400"
            >
              {{ event.name }}
            </router-link>
            <!-- Escape hatch for when the derived focus guesses wrong (two
                 overlapping trips, or planning next summer during this one). -->
            <Menu v-if="otherEvents.length > 0" as="div">
              <!-- The chevron reads as a 28px control but takes pointer input
                   across 44px (`after` inset, no layout cost): WCAG 2.5.8 asks
                   for 24, touch asks for more, and the bar is on every page so
                   it can't afford to grow. Its neighbours above and below are
                   plain text, so the overspill catches nothing else.

                   The label names the action and nothing else. Folding the
                   event name in makes the button answer to that name, for
                   role-name queries and AT users alike, when the name belongs
                   to the link beside it and reading order already supplies it. -->
              <MenuButton
                data-testid="focus-switcher-trigger"
                aria-label="Switch event"
                class="text-ink-muted hover:bg-surface-page hover:text-ink focus-visible:outline-focus relative flex size-7 shrink-0 items-center justify-center rounded-md transition-colors after:absolute after:-inset-2 after:content-[''] focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                <ChevronDownIcon class="size-5" aria-hidden="true" />
              </MenuButton>
              <transition
                enter-active-class="transition ease-out duration-100"
                enter-from-class="transform opacity-0 scale-95"
                enter-to-class="transform opacity-100 scale-100"
                leave-active-class="transition ease-in duration-75"
                leave-from-class="transform opacity-100 scale-100"
                leave-to-class="transform opacity-0 scale-95"
              >
                <MenuItems
                  class="bg-surface ring-ring-hairline absolute top-full left-0 z-20 mt-2 w-64 max-w-[calc(100vw-2rem)] origin-top-left rounded-md py-1 shadow-lg ring-1 focus:outline-hidden"
                >
                  <MenuItem
                    v-for="other in otherEvents"
                    :key="other.id"
                    v-slot="{ active }"
                  >
                    <button
                      type="button"
                      data-testid="focus-switcher-option"
                      :data-event-id="other.id"
                      :class="[
                        active ? 'bg-btn-secondary-fill' : '',
                        'text-ink block w-full px-4 py-2 text-left text-sm',
                      ]"
                      @click="switchTo(other.id)"
                    >
                      <span class="block truncate">{{ other.name }}</span>
                      <DateRangeDisplay
                        v-if="other.startDate && other.endDate"
                        :start-date="other.startDate"
                        :end-date="other.endDate"
                        class="text-ink-muted block text-xs"
                      />
                    </button>
                  </MenuItem>
                </MenuItems>
              </transition>
            </Menu>
          </div>
          <p
            v-if="eventHasDates(props.event)"
            data-testid="event-dates"
            class="text-ink-muted hidden items-center gap-1 text-xs sm:flex"
          >
            <CalendarDaysIcon class="size-3.5" />
            <DateRangeDisplay
              :start-date="event.startDate!"
              :end-date="event.endDate!"
            />
          </p>
        </div>
        <nav
          data-testid="event-tabs"
          class="-mx-4 mt-1 flex items-center gap-1 overflow-x-auto px-4 sm:mx-0 sm:mt-0 sm:px-0"
        >
          <router-link
            :to="`/events/${eventId}/planning`"
            :class="tabClass(activeTab === 'planning')"
          >
            Planning
          </router-link>
          <router-link
            :to="`/events/${eventId}/rsvp`"
            :class="tabClass(activeTab === 'rsvp')"
          >
            RSVP
          </router-link>
          <router-link
            :to="`/events/${eventId}/days`"
            :class="tabClass(activeTab === 'days')"
          >
            Days
          </router-link>
          <router-link
            :to="`/events/${eventId}/expenses`"
            :class="tabClass(activeTab === 'expenses')"
          >
            Expenses
          </router-link>
          <router-link
            :to="`/events/${eventId}/chores`"
            :class="tabClass(activeTab === 'chores')"
          >
            Chores
          </router-link>
        </nav>
      </div>
    </div>
  </div>
</template>
