<script setup lang="ts">
import { CakeIcon } from '@heroicons/vue/24/outline'
import { formatUpcomingBirthday } from '@/utils/date'
import { useLocale } from '@/composables/useLocale'
import { getInitials } from '@/utils/member'
import BaseCard from '@/components/common/BaseCard.vue'
import AppAvatar from '@/components/common/AppAvatar.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import type { PoolMember } from '@/types/pool'

defineProps<{
  members: PoolMember[]
}>()

const { locale } = useLocale()
</script>

<template>
  <section>
    <SectionHeading :icon="CakeIcon" title="Upcoming birthdays" />

    <ul class="space-y-3">
      <!-- Explicit birthday check in the loop itself, rather than relying on
           the caller to have pre-filtered `members` — keeps this component
           safe to reuse even if a future caller passes an unfiltered list. -->
      <template v-for="member in members" :key="member.id">
        <BaseCard v-if="member.birthday" as="li" class="overflow-hidden">
          <div class="flex items-center gap-4 px-4 py-4 sm:px-6">
            <AppAvatar :initials="getInitials(member)" />
            <div class="min-w-0 flex-1">
              <h3 class="text-ink truncate text-base font-semibold">
                {{ member.name || member.email }}
              </h3>
              <div
                class="text-ink-muted mt-0.5 flex items-center gap-1 text-sm"
              >
                <CakeIcon class="size-4" />
                {{ formatUpcomingBirthday(member.birthday, locale) }}
              </div>
            </div>
          </div>
        </BaseCard>
      </template>
    </ul>
  </section>
</template>
