<script setup lang="ts">
import { useAuth } from '@/composables/useAuth'

const { user } = useAuth()
</script>

<template>
  <div>
    <header class="mb-6">
      <h1 class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        Profile
      </h1>
    </header>

    <div class="bg-white dark:bg-gray-800 overflow-hidden shadow rounded-lg">
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

          <div class="border-t border-gray-200 dark:border-gray-700 pt-6">
            <dl class="divide-y divide-gray-200 dark:divide-gray-700">
              <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
                <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                  Email address
                </dt>
                <dd class="mt-1 text-sm text-gray-900 dark:text-white sm:col-span-2 sm:mt-0">
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
