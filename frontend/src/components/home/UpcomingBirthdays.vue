<script setup lang="ts">
import { CakeIcon } from '@heroicons/vue/24/outline'
import { formatBirthday } from '@/utils/date'
import { getInitials } from '@/utils/member'
import BaseCard from '@/components/common/BaseCard.vue'
import AppAvatar from '@/components/common/AppAvatar.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import type { PoolMember } from '@/types/pool'

defineProps<{
  members: PoolMember[]
}>()

function formatBirthdayDate(member: PoolMember): string {
  if (!member.birthday) return ''
  const today = new Date()
  const [, month, day] = member.birthday.split('-')
  for (let i = 1; i <= 7; i++) {
    const future = new Date(today)
    future.setDate(future.getDate() + i)
    if (
      Number(month) === future.getMonth() + 1 &&
      Number(day) === future.getDate()
    ) {
      if (i === 1) return 'Tomorrow'
      return future.toLocaleDateString(undefined, {
        weekday: 'long',
      })
    }
  }
  return formatBirthday(member.birthday)
}
</script>

<template>
  <section>
    <SectionHeading :icon="CakeIcon" title="Upcoming birthdays" />

    <ul class="space-y-3">
      <BaseCard
        v-for="member in members"
        :key="member.id"
        as="li"
        class="overflow-hidden"
      >
        <div class="flex items-center gap-4 px-4 py-4 sm:px-6">
          <AppAvatar :initials="getInitials(member)" />
          <div class="min-w-0 flex-1">
            <h3 class="text-ink truncate text-base font-semibold">
              {{ member.name || member.email }}
            </h3>
            <div class="text-ink-muted mt-0.5 flex items-center gap-1 text-sm">
              <CakeIcon class="size-4" />
              {{ formatBirthdayDate(member) }}
            </div>
          </div>
        </div>
      </BaseCard>
    </ul>
  </section>
</template>
