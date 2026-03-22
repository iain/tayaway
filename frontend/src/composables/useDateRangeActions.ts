import { useActionTrigger } from './useActionTrigger'

export function useDateRangeActions() {
  const { pending: pendingAdd, trigger: triggerAdd, reset: resetAdd } =
    useActionTrigger()
  return { pendingAdd, triggerAdd, resetAdd }
}
