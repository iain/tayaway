<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useAuthStore } from '@/stores'
import EditNameModal from '@/components/profile/EditNameModal.vue'
import SessionsList from '@/components/profile/SessionsList.vue'

const authStore = useAuthStore()
const { user } = storeToRefs(authStore)

const editNameOpen = ref(false)
const editNameLoading = ref(false)
const editNameError = ref<string | null>(null)

async function handleSaveName(name: string): Promise<void> {
  editNameLoading.value = true
  editNameError.value = null
  try {
    await authStore.updateName(name)
    editNameOpen.value = false
  } catch {
    editNameError.value = 'Failed to update name. Please try again.'
  } finally {
    editNameLoading.value = false
  }
}
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
                  Name
                </dt>
                <dd
                  class="mt-1 flex items-center gap-2 text-sm text-gray-900 sm:col-span-2 sm:mt-0 dark:text-white"
                >
                  <span>{{ user?.name ?? 'Not set' }}</span>
                  <button
                    type="button"
                    class="text-sm font-medium text-rose-500 hover:text-rose-400"
                    @click="editNameOpen = true"
                  >
                    Edit
                  </button>
                </dd>
              </div>
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
    <SessionsList class="mt-6" />
    <EditNameModal
      :open="editNameOpen"
      :loading="editNameLoading"
      :current-name="user?.name ?? null"
      @close="editNameOpen = false"
      @save="handleSaveName"
    />
  </div>
</template>
