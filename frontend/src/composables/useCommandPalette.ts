import { ref } from 'vue'

const isOpen = ref(false)

export function useCommandPalette() {
  function open() {
    isOpen.value = true
  }

  return { isOpen, open }
}
