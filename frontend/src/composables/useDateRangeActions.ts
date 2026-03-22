import { useActionTrigger } from './useActionTrigger'

export function useDateRangeActions() {
  const { pending: pendingAdd, trigger: triggerAdd } =
    useActionTrigger('dateRangeAdd')
  return { pendingAdd, triggerAdd }
}
