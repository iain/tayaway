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
  >
    <div class="flex items-center gap-4 px-4 py-4 sm:px-6">
      <AppAvatar :initials="getInitials(member)" class="shrink-0" />

      <div class="min-w-0 flex-1">
        <div class="flex items-baseline justify-between gap-2">
          <h3 class="text-ink truncate text-base font-semibold">
            {{ member.name || member.email }}
          </h3>
          <!-- Screen readers get one calm announcement ("Alice Smith. Birthday
               Tomorrow.") from the name plus this label; the visual pill and
               the per-second ticking below are aria-hidden, so nothing is read
               twice or ticked out loud. -->
          <span class="sr-only">Birthday {{ label }}</span>
          <span
            class="bday-label shrink-0 rounded-full px-2 py-0.5 text-xs font-medium"
            aria-hidden="true"
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

        <!-- Loading line: a quiet flavour phrase, live percentage, and a bar
             that fills as the day approaches. -->
        <div class="mt-2" aria-hidden="true">
          <div class="mb-1.5 flex items-center justify-between gap-2 text-xs">
            <span class="bday-phrase text-ink-muted min-w-0 truncate">
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

/* "Tomorrow" / weekday pill — the calm, glanceable label. Its dark-mode colour
   lives here rather than in a `dark:` utility so the value swaps through the
   same `:where(.dark)` token pattern the rest of this file uses. */
.bday-label {
  background: var(--color-amber-100);
  color: var(--color-amber-700);
}
:where(.dark) .bday-label {
  background: color-mix(in oklab, var(--color-amber-500) 15%, transparent);
  color: var(--color-amber-300);
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
  overflow: hidden;
  background: linear-gradient(
    90deg,
    var(--color-amber-400),
    var(--color-pink-400)
  );
  /* No width transition: `percent` is whole-number over a 7-day window, so it
     steps by 1% only every ~100 minutes — a glide there would be imperceptible
     and would animate a layout property, which the system forbids. */
}

/* Moving sheen sweeping across the filled portion. Animates `transform`
   (compositor-only) rather than `background-position` (which repaints every
   frame), so the perpetual sweep stays off the main thread. Clipped to the
   filled area by the parent's `overflow: hidden`. */
.bday-bar-fill::after {
  content: '';
  position: absolute;
  top: 0;
  bottom: 0;
  left: 0;
  width: 60%;
  background: linear-gradient(
    90deg,
    transparent,
    rgba(255, 255, 255, 0.55),
    transparent
  );
  animation: bday-sheen 2s linear infinite;
}

@keyframes bday-sheen {
  from {
    transform: translateX(-100%);
  }
  to {
    transform: translateX(250%);
  }
}

/* Respect reduced-motion: the informational countdown keeps ticking; the only
   decorative animation left — the progress-bar sheen — freezes. */
@media (prefers-reduced-motion: reduce) {
  .bday-bar-fill::after {
    animation: none;
  }
}
</style>
