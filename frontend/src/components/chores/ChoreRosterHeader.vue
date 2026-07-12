<script setup lang="ts">
import { ClipboardDocumentListIcon } from '@heroicons/vue/24/outline'
import PageHeader from '@/components/common/PageHeader.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'

// A roster is a whole page under an event (`page`) and one region among several
// on the standalone chores page (`section`). Same content, two altitudes.
defineProps<{
  title: string
  subtitle?: string
  headingStyle: 'page' | 'section'
}>()
</script>

<template>
  <PageHeader
    v-if="headingStyle === 'page'"
    :title="title"
    size="sm"
    :icon="ClipboardDocumentListIcon"
  >
    <slot />
  </PageHeader>
  <SectionHeading
    v-else
    :icon="ClipboardDocumentListIcon"
    :title="title"
    :subtitle="subtitle"
  >
    <slot />
  </SectionHeading>
</template>
