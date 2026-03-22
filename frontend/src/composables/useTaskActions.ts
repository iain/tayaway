import { ref } from 'vue'
import { useActionTrigger } from './useActionTrigger'

const pendingNewListRef = ref(false)

export function useTaskActions() {
  const {
    pending: pendingNewList,
    trigger: triggerNewList,
    reset: resetNewList,
  } = useActionTrigger(pendingNewListRef)
  return { pendingNewList, triggerNewList, resetNewList }
}
