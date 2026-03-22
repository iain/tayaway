import { ref, type Ref } from 'vue'

export function useActionTrigger(pending?: Ref<boolean>) {
  const _pending = pending ?? ref(false)

  function trigger() {
    _pending.value = true
  }

  function reset() {
    _pending.value = false
  }

  return { pending: _pending, trigger, reset }
}
