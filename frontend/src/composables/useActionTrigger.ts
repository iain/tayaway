import { ref, type Ref } from 'vue'

const triggers = new Map<string, Ref<boolean>>()

export function useActionTrigger(key: string) {
  if (!triggers.has(key)) {
    triggers.set(key, ref(false))
  }
  const pending = triggers.get(key)!

  function trigger() {
    pending.value = true
  }

  return { pending, trigger }
}
