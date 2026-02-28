<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseModal from '@/components/common/BaseModal.vue'
import FormInput from '@/components/form/FormInput.vue'
import FormActions from '@/components/form/FormActions.vue'
import { useChoreRostersStore } from '@/stores/choreRosters'

const props = defineProps<{
  open: boolean
  rosterId: string
}>()

const emit = defineEmits<{
  close: []
}>()

const choreRostersStore = useChoreRostersStore()

const name = ref('')
const peoplePerDay = ref('1')
const submitting = ref(false)

watch(
  () => props.open,
  (isOpen) => {
    if (isOpen) {
      name.value = ''
      peoplePerDay.value = '1'
    }
  }
)

async function handleSubmit() {
  if (!name.value.trim()) return

  submitting.value = true
  try {
    await choreRostersStore.addChore(
      props.rosterId,
      name.value.trim(),
      parseInt(peoplePerDay.value, 10) || 1
    )
    emit('close')
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <BaseModal :open="open" title="Add Chore" size="sm" @close="$emit('close')">
    <form @submit.prevent="handleSubmit">
      <div class="space-y-4">
        <FormInput
          id="chore-name"
          v-model="name"
          label="Name"
          placeholder="e.g. Cooking, Washing up"
          required
          :maxlength="255"
        />
        <FormInput
          id="chore-ppd"
          v-model="peoplePerDay"
          label="People per day"
          type="number"
          placeholder="1"
          :min="1"
          :max="50"
        />
      </div>
      <FormActions
        submit-label="Add"
        :loading="submitting"
        loading-label="Adding..."
        @cancel="$emit('close')"
      />
    </form>
  </BaseModal>
</template>
