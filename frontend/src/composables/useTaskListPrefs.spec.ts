import { describe, it, expect, beforeEach } from 'vitest'
import { useTaskListPrefs } from './useTaskListPrefs'

const STORAGE_KEY = 'tayaway:tasks:collapsed-lists'

describe('useTaskListPrefs', () => {
  beforeEach(() => {
    // The composable keeps module-level state, so tests reset through the
    // public API rather than reloading the module.
    const { isListCollapsed, setListCollapsed } = useTaskListPrefs()
    for (const id of ['list-1', 'list-2']) {
      if (isListCollapsed(id)) setListCollapsed(id, false)
    }
    localStorage.removeItem(STORAGE_KEY)
  })

  it('defaults every list to expanded', () => {
    const { isListCollapsed } = useTaskListPrefs()
    expect(isListCollapsed('list-1')).toBe(false)
  })

  it('toggles collapse state per list', () => {
    const { isListCollapsed, toggleListCollapsed } = useTaskListPrefs()

    toggleListCollapsed('list-1')
    expect(isListCollapsed('list-1')).toBe(true)
    expect(isListCollapsed('list-2')).toBe(false)

    toggleListCollapsed('list-1')
    expect(isListCollapsed('list-1')).toBe(false)
  })

  it('persists collapsed lists to localStorage', () => {
    const { setListCollapsed } = useTaskListPrefs()

    setListCollapsed('list-1', true)

    expect(JSON.parse(localStorage.getItem(STORAGE_KEY)!)).toEqual({
      'list-1': true,
    })
  })

  it('prunes expanded lists from storage instead of storing false', () => {
    const { setListCollapsed } = useTaskListPrefs()

    setListCollapsed('list-1', true)
    setListCollapsed('list-2', true)
    setListCollapsed('list-1', false)

    expect(JSON.parse(localStorage.getItem(STORAGE_KEY)!)).toEqual({
      'list-2': true,
    })
  })
})
