import { ref } from 'vue'

const pendingNewList = ref(false)

export function useTaskActions() {
  function triggerNewList() {
    pendingNewList.value = true
  }

  return { pendingNewList, triggerNewList }
}
