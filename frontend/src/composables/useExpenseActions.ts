import { useActionTrigger } from './useActionTrigger'

export function useExpenseActions() {
  const { pending: pendingAdd, trigger: triggerAdd, reset: resetAdd } =
    useActionTrigger()
  return { pendingAdd, triggerAdd, resetAdd }
}
