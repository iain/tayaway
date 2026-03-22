import { useActionTrigger } from './useActionTrigger'

export function useExpenseActions() {
  const { pending: pendingAdd, trigger: triggerAdd } =
    useActionTrigger('expenseAdd')
  return { pendingAdd, triggerAdd }
}
