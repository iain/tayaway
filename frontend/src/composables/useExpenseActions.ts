import { ref } from 'vue'
import { useActionTrigger } from './useActionTrigger'

const pendingAddRef = ref(false)

export function useExpenseActions() {
  const {
    pending: pendingAdd,
    trigger: triggerAdd,
    reset: resetAdd,
  } = useActionTrigger(pendingAddRef)
  return { pendingAdd, triggerAdd, resetAdd }
}
