<script setup lang="ts">
import type { PoolMember } from '@/types/pool'

defineProps<{
  members: PoolMember[]
}>()
</script>

<template>
  <section>
    <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
      🎂 Happy Birthday!
    </h2>

    <ul class="space-y-3">
      <li
        v-for="member in members"
        :key="member.id"
        class="birthday-card-dashboard overflow-hidden rounded-lg shadow"
      >
        <div class="flex items-center gap-4 px-4 py-4 sm:px-6">
          <div
            class="flex size-10 shrink-0 animate-bounce items-center justify-center rounded-full bg-amber-300 text-lg ring-4 ring-amber-400/50 dark:bg-amber-500 dark:ring-amber-500/50"
          >
            🎂
          </div>
          <div class="min-w-0 flex-1">
            <h3
              class="truncate text-base font-semibold text-gray-900 dark:text-white"
            >
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
    #fef3c7 0%,
    #fce7f3 25%,
    #ede9fe 50%,
    #dbeafe 75%,
    #fef3c7 100%
  );
  background-size: 300% 300%;
  animation: birthday-gradient 4s ease infinite;
}

:where(.dark) .birthday-card-dashboard {
  background: linear-gradient(
    135deg,
    #78350f 0%,
    #831843 25%,
    #4c1d95 50%,
    #1e3a5f 75%,
    #78350f 100%
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
    #f59e0b,
    #ec4899,
    #8b5cf6,
    #f59e0b,
    #ec4899
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
