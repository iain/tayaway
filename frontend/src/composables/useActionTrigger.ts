import { ref } from 'vue'

export function useActionTrigger() {
  const pending = ref(false)

  function trigger() {
    pending.value = true
  }

  function reset() {
    pending.value = false
  }

  return { pending, trigger, reset }
}
