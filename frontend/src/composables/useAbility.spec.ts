import { describe, it, expect } from 'vitest'
import { computed, ref } from 'vue'
import { useAbility } from './useAbility'
import type { AbilityResult } from '@/types/pool'

describe('useAbility', () => {
  it('returns denied and hidden when object is undefined', () => {
    const obj = ref(undefined)
    const { allowed, visible, hint } = useAbility(obj, 'update')

    expect(allowed.value).toBe(false)
    expect(visible.value).toBe(false)
    expect(hint.value).toBe('hidden')
  })

  it('returns denied and hidden when abilities are missing', () => {
    const obj = ref<{ abilities?: Record<string, AbilityResult> } | undefined>(
      {}
    )
    const { allowed, visible } = useAbility(obj, 'update')

    expect(allowed.value).toBe(false)
    expect(visible.value).toBe(false)
  })

  it('returns denied and hidden when specific ability is missing', () => {
    const obj = ref({
      id: '1',
      objectType: 'event' as const,
      updatedAt: '',
      abilities: { delete: { allowed: true } },
    })
    const { allowed, visible } = useAbility(obj, 'update')

    expect(allowed.value).toBe(false)
    expect(visible.value).toBe(false)
  })

  it('returns allowed when ability is granted', () => {
    const obj = ref({
      id: '1',
      objectType: 'event' as const,
      updatedAt: '',
      abilities: { update: { allowed: true } },
    })
    const { allowed, visible, reason } = useAbility(obj, 'update')

    expect(allowed.value).toBe(true)
    expect(visible.value).toBe(true)
    expect(reason.value).toBeUndefined()
  })

  it('returns denied and hidden for denied ability with default hint', () => {
    const obj = ref({
      id: '1',
      objectType: 'event' as const,
      updatedAt: '',
      abilities: {
        update: {
          allowed: false,
          reason: 'not_owner',
          hint: 'hidden' as const,
        },
      },
    })
    const { allowed, visible, reason, hint } = useAbility(obj, 'update')

    expect(allowed.value).toBe(false)
    expect(visible.value).toBe(false)
    expect(reason.value).toBe('not_owner')
    expect(hint.value).toBe('hidden')
  })

  it('returns denied but visible for disabled hint', () => {
    const obj = ref({
      id: '1',
      objectType: 'event' as const,
      updatedAt: '',
      abilities: {
        delete: {
          allowed: false,
          reason: 'has_expenses',
          hint: 'disabled' as const,
        },
      },
    })
    const { allowed, visible, reason } = useAbility(obj, 'delete')

    expect(allowed.value).toBe(false)
    expect(visible.value).toBe(true)
    expect(reason.value).toBe('has_expenses')
  })

  it('reacts to object changes', () => {
    const obj = ref<{ abilities?: Record<string, AbilityResult> } | undefined>({
      abilities: {
        update: { allowed: false, reason: 'not_owner', hint: 'hidden' },
      },
    })
    const { allowed, visible } = useAbility(obj, 'update')

    expect(allowed.value).toBe(false)
    expect(visible.value).toBe(false)

    obj.value = {
      abilities: { update: { allowed: true } },
    }

    expect(allowed.value).toBe(true)
    expect(visible.value).toBe(true)
  })

  it('works with computed refs', () => {
    const raw = ref({ abilities: { update: { allowed: true } } })
    const obj = computed(() => raw.value)
    const { allowed } = useAbility(obj, 'update')

    expect(allowed.value).toBe(true)
  })
})
