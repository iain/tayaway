<script setup lang="ts">
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores'

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)
</script>

<template>
  <div>
    <header class="mb-6">
      <h1
        class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
      >
        Profile
      </h1>
    </header>

    <div class="overflow-hidden rounded-lg bg-white shadow dark:bg-gray-800">
      <div class="px-4 py-5 sm:p-6">
        <div class="space-y-6">
          <div>
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">
              Account Information
            </h3>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              Your account details.
            </p>
          </div>

          <div class="border-t border-gray-200 pt-6 dark:border-gray-700">
            <dl class="divide-y divide-gray-200 dark:divide-gray-700">
              <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
                <dt
                  class="text-sm font-medium text-gray-500 dark:text-gray-400"
                >
                  Email address
                </dt>
                <dd
                  class="mt-1 text-sm text-gray-900 sm:col-span-2 sm:mt-0 dark:text-white"
                >
                  {{ user?.email }}
                </dd>
              </div>
            </dl>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
