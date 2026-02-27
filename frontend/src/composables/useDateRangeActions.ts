import { ref } from 'vue'

const pendingAdd = ref(false)

export function useDateRangeActions() {
  function triggerAdd() {
    pendingAdd.value = true
  }

  return { pendingAdd, triggerAdd }
}
