<script setup lang="ts">
import { GiftIcon } from '@heroicons/vue/24/outline'
import SectionHeading from '@/components/common/SectionHeading.vue'
import BirthdayCountdownCard from '@/components/home/BirthdayCountdownCard.vue'
import type { PoolMember } from '@/types/pool'

defineProps<{
  members: PoolMember[]
}>()
</script>

<template>
  <section>
    <SectionHeading :icon="GiftIcon" title="Upcoming birthdays" />

    <ul class="space-y-3">
      <!-- Each card guards its own birthday internally (renders nothing without
           one), so this stays safe even if a future caller passes an
           unfiltered member list. -->
      <BirthdayCountdownCard
        v-for="member in members"
        :key="member.id"
        :member="member"
      />
    </ul>
  </section>
</template>
