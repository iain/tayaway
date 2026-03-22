import { useActionTrigger } from './useActionTrigger'

export function useTaskActions() {
  const { pending: pendingNewList, trigger: triggerNewList, reset: resetNewList } =
    useActionTrigger()
  return { pendingNewList, triggerNewList, resetNewList }
}
