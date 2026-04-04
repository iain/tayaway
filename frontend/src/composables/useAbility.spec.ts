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
      abilities: { delete: { allowed: true } },
    })
    const { allowed, visible } = useAbility(obj, 'update')

    expect(allowed.value).toBe(false)
    expect(visible.value).toBe(false)
  })

  it('returns allowed when ability is granted', () => {
    const obj = ref({
      abilities: { update: { allowed: true } },
    })
    const { allowed, visible, reason } = useAbility(obj, 'update')

    expect(allowed.value).toBe(true)
    expect(visible.value).toBe(true)
    expect(reason.value).toBeUndefined()
  })

  it('hides denied abilities with permanent reasons like not_owner', () => {
    const obj = ref({
      abilities: { update: { allowed: false, reason: 'not_owner' } },
    })
    const { allowed, visible, hint } = useAbility(obj, 'update')

    expect(allowed.value).toBe(false)
    expect(visible.value).toBe(false)
    expect(hint.value).toBe('hidden')
  })

  it('shows disabled for situational reasons like has_expenses', () => {
    const obj = ref({
      abilities: { delete: { allowed: false, reason: 'has_expenses' } },
    })
    const { allowed, visible, hint, reason } = useAbility(obj, 'delete')

    expect(allowed.value).toBe(false)
    expect(visible.value).toBe(true)
    expect(hint.value).toBe('disabled')
    expect(reason.value).toBe('has_expenses')
  })

  it('shows disabled for has_settlements reason', () => {
    const obj = ref({
      abilities: { delete: { allowed: false, reason: 'has_settlements' } },
    })
    const { hint } = useAbility(obj, 'delete')

    expect(hint.value).toBe('disabled')
  })

  it('reacts to object changes', () => {
    const obj = ref<{ abilities?: Record<string, AbilityResult> } | undefined>({
      abilities: { update: { allowed: false, reason: 'not_owner' } },
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
