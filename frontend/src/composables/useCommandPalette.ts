import { ref, shallowRef, type Component } from 'vue'

export interface ContextAction {
  id: string
  name: string
  icon: Component
  href?: string
  run?: () => void | Promise<void>
}

export interface ContextGroup {
  label: string
  actions: ContextAction[]
}

const isOpen = ref(false)
const contextGroups = shallowRef<Map<string, ContextGroup>>(new Map())

export function useCommandPalette() {
  function open() {
    isOpen.value = true
  }

  function setContext(key: string, group: ContextGroup | null) {
    const next = new Map(contextGroups.value)
    if (group && group.actions.length > 0) {
      next.set(key, group)
    } else {
      next.delete(key)
    }
    contextGroups.value = next
  }

  return { isOpen, open, contextGroups, setContext }
}
