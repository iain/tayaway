import { useActionTrigger } from './useActionTrigger'

export function useTaskActions() {
  const { pending: pendingNewList, trigger: triggerNewList } =
    useActionTrigger('taskNewList')
  return { pendingNewList, triggerNewList }
}
