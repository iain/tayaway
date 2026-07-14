<script setup lang="ts">
import { DateTime } from 'luxon'
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
  // Anchor to the start of today in local time so the comparison is pure
  // calendar math, unaffected by the current time-of-day.
  const today = DateTime.local().startOf('day')
  const [, monthStr, dayStr] = member.birthday.split('-')
  const month = Number(monthStr)
  const day = Number(dayStr)

  for (let i = 1; i <= 7; i++) {
    const future = today.plus({ days: i })
    if (future.month === month && future.day === day) {
      if (i === 1) {
        // toRelativeCalendar gives us the localized "tomorrow" label.
        return future.toRelativeCalendar({ base: today }) ?? 'Tomorrow'
      }
      return future.toFormat('cccc')
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
