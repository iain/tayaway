<script setup lang="ts">
import { GiftIcon } from '@heroicons/vue/24/outline'
import SectionHeading from '@/components/common/SectionHeading.vue'
import type { PoolMember } from '@/types/pool'

defineProps<{
  members: PoolMember[]
}>()
</script>

<template>
  <section>
    <SectionHeading :icon="GiftIcon" title="Happy Birthday!" />

    <ul class="space-y-3">
      <li
        v-for="member in members"
        :key="member.id"
        class="birthday-card-dashboard overflow-hidden rounded-lg shadow"
      >
        <div class="flex items-center gap-4 px-4 py-4 sm:px-6">
          <div
            class="flex size-10 shrink-0 items-center justify-center rounded-full bg-amber-300 text-lg ring-4 ring-amber-400/50 dark:bg-amber-500 dark:ring-amber-500/50"
          >
            🎂
          </div>
          <div class="min-w-0 flex-1">
            <h3 class="text-ink truncate text-base font-semibold">
              {{ member.name || member.email }}
            </h3>
            <p class="birthday-shimmer text-sm font-bold">
              🎉 It's their birthday today! 🎉
            </p>
          </div>
          <span class="text-2xl">🥳</span>
        </div>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.birthday-card-dashboard {
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
}

:where(.dark) .birthday-card-dashboard {
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
