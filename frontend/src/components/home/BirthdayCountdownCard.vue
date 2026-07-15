<script setup lang="ts">
import { computed } from 'vue'
import { useSecondTicker } from '@/composables/useSecondTicker'
import { useLocale } from '@/composables/useLocale'
import { formatUpcomingBirthday, getBirthdayCountdown } from '@/utils/date'
import { pickBirthdayPhrase } from '@/utils/birthdayPhrases'
import { getInitials } from '@/utils/member'
import AppAvatar from '@/components/common/AppAvatar.vue'
import type { PoolMember } from '@/types/pool'

const props = defineProps<{
  member: PoolMember
}>()

const { locale } = useLocale()
const { now } = useSecondTicker()

// How often the loading phrase swaps, in ms — slow enough to read, brisk
// enough to feel like a real loading screen churning through tasks.
const PHRASE_ROTATION_MS = 3_500

// Display-ready countdown ({ text, percent }); all date math lives in date.ts.
const countdown = computed(() =>
  props.member.birthday
    ? getBirthdayCountdown(props.member.birthday, now.value)
    : null
)

// Human label ("Tomorrow", "Tuesday", "Next Monday") shown as a pill — the
// calm, glanceable counterpart to the ticking countdown.
const label = computed(() =>
  props.member.birthday
    ? formatUpcomingBirthday(props.member.birthday, locale.value)
    : ''
)

// Rotate the flavor text on a time bucket, seeded per member so neighbouring
// cards churn through different tasks at any given moment.
const phrase = computed(() => {
  const bucket = Math.floor(now.value / PHRASE_ROTATION_MS)
  return pickBirthdayPhrase(`${props.member.id}:${bucket}`)
})
</script>

<template>
  <li
    v-if="countdown"
    class="bday-countdown-card bg-surface ring-ring-hairline overflow-hidden rounded-lg shadow ring-1 dark:shadow-[0_2px_8px_rgba(0,0,0,0.25),inset_0_1px_0_rgba(255,255,255,0.06)]"
    :aria-label="`${member.name || member.email}: birthday ${label.toLowerCase()}`"
  >
    <div class="flex items-center gap-4 px-4 py-4 sm:px-6">
      <!-- Avatar wrapped in a slowly spinning gradient ring — the birthday is
           quite literally "loading". Only the ring (a pseudo-element) spins;
           the avatar sits still on top so the initials stay upright. -->
      <div
        class="bday-ring relative shrink-0 rounded-full p-[2px]"
        aria-hidden="true"
      >
        <AppAvatar :initials="getInitials(member)" class="relative z-10" />
      </div>

      <div class="min-w-0 flex-1">
        <div class="flex items-baseline justify-between gap-2">
          <h3 class="text-ink truncate text-base font-semibold">
            {{ member.name || member.email }}
          </h3>
          <span
            class="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700 dark:bg-amber-500/15 dark:text-amber-300"
          >
            {{ label }}
          </span>
        </div>

        <!-- The ticking payoff. aria-hidden so screen readers get the calm
             label above instead of a countdown read out every second. -->
        <p
          class="bday-countdown mt-1.5 font-semibold tabular-nums"
          aria-hidden="true"
        >
          {{ countdown.text }}
        </p>

        <!-- Loading line: shimmering flavor phrase, live percentage, and a bar
             that fills as the day approaches. -->
        <div class="mt-2" aria-hidden="true">
          <div class="mb-1 flex items-center justify-between gap-2 text-xs">
            <span class="bday-phrase min-w-0 truncate font-medium">
              🎂 {{ phrase }}
            </span>
            <span class="text-ink-muted shrink-0 tabular-nums"
              >{{ countdown.percent }}%</span
            >
          </div>
          <div class="bday-bar-track">
            <div
              class="bday-bar-fill"
              :style="{ width: `${countdown.percent}%` }"
            />
          </div>
        </div>
      </div>
    </div>
  </li>
</template>

<style scoped>
.bday-countdown {
  color: var(--color-amber-600);
  font-size: 1.125rem;
  line-height: 1;
  letter-spacing: 0.04em;
}
:where(.dark) .bday-countdown {
  color: var(--color-amber-400);
}

/* Spinning gradient ring around the avatar — a birthday "spinner". The
   gradient lives on a pseudo-element behind the avatar so only the rim spins;
   the avatar's opaque fill masks all but the 2px padding, leaving a ring. */
.bday-ring::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: 0;
  border-radius: 9999px;
  background: conic-gradient(
    from 0deg,
    var(--color-amber-400),
    var(--color-pink-400),
    var(--color-violet-400),
    var(--color-amber-400)
  );
  animation: bday-spin 3.5s linear infinite;
}

@keyframes bday-spin {
  to {
    transform: rotate(360deg);
  }
}

/* Gradient-clipped, shimmering loading phrase. */
.bday-phrase {
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
  animation: bday-shimmer 3s linear infinite;
}

@keyframes bday-shimmer {
  to {
    background-position: 200% center;
  }
}

.bday-bar-track {
  height: 6px;
  border-radius: 9999px;
  overflow: hidden;
  background: var(--color-amber-100);
}
:where(.dark) .bday-bar-track {
  background: color-mix(in oklab, var(--color-amber-900) 55%, transparent);
}

.bday-bar-fill {
  position: relative;
  height: 100%;
  border-radius: 9999px;
  background: linear-gradient(
    90deg,
    var(--color-amber-400),
    var(--color-pink-400)
  );
  /* Glide between per-second width steps instead of snapping. */
  transition: width 1s linear;
}

/* Moving sheen sweeping across the filled portion. */
.bday-bar-fill::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    90deg,
    transparent,
    rgba(255, 255, 255, 0.55),
    transparent
  );
  background-size: 200% 100%;
  animation: bday-sheen 2s linear infinite;
}

@keyframes bday-sheen {
  to {
    background-position: -200% 0;
  }
}

/* Respect reduced-motion: keep the informational countdown ticking, but calm
   every decorative animation to a static state. */
@media (prefers-reduced-motion: reduce) {
  .bday-ring::before,
  .bday-phrase,
  .bday-bar-fill,
  .bday-bar-fill::after {
    animation: none;
  }
  .bday-bar-fill {
    transition: none;
  }
  .bday-phrase {
    background: none;
    -webkit-text-fill-color: currentColor;
    color: var(--color-amber-600);
  }
  :where(.dark) .bday-phrase {
    color: var(--color-amber-400);
  }
}
</style>
