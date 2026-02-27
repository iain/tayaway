import { ref } from 'vue'

const pendingAdd = ref(false)

export function useExpenseActions() {
  function triggerAdd() {
    pendingAdd.value = true
  }

  return { pendingAdd, triggerAdd }
}
