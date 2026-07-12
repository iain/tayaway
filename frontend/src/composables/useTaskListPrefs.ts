import { ref, watch } from 'vue'

// Per-list collapsed state for the Tasks page accordion, persisted so the
// lists you tucked away stay tucked away across visits. This is a personal
// UI preference — it deliberately lives in localStorage and not in the
// shared object pool, so collapsing a list never collapses it for anyone
// else in the workspace.
const STORAGE_KEY = 'tayaway:tasks:collapsed-lists'

function load(): Record<string, true> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) {
      const parsed: unknown = JSON.parse(raw)
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed as Record<string, true>
      }
    }
  } catch {
    // Inaccessible or corrupted storage falls back to everything expanded.
  }
  return {}
}

const collapsedLists = ref<Record<string, true>>(load())

watch(
  collapsedLists,
  (value) => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(value))
    } catch {
      // Best effort — private mode or a full quota just loses persistence.
    }
  },
  { deep: true }
)

export function useTaskListPrefs() {
  function isListCollapsed(listId: string): boolean {
    return collapsedLists.value[listId] === true
  }

  // Only collapsed ids are stored (expanded is the default), so the map
  // self-prunes as lists get expanded or deleted-then-expanded elsewhere.
  function setListCollapsed(listId: string, collapsed: boolean): void {
    if (collapsed) {
      collapsedLists.value[listId] = true
    } else {
      delete collapsedLists.value[listId]
    }
  }

  function toggleListCollapsed(listId: string): void {
    setListCollapsed(listId, !isListCollapsed(listId))
  }

  return { isListCollapsed, setListCollapsed, toggleListCollapsed }
}
