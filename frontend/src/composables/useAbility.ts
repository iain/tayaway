import { computed, type ComputedRef, type Ref } from 'vue'
import type { AbilityResult } from '@/types/pool'

type Hint = 'hidden' | 'disabled'

interface AbilityCheck {
  /** Whether the action is allowed */
  allowed: ComputedRef<boolean>
  /** Machine-readable reason code (e.g. "not_owner", "has_expenses") */
  reason: ComputedRef<string | undefined>
  /** UI hint derived from the reason: "hidden" or "disabled" */
  hint: ComputedRef<Hint>
  /** Whether the UI control should be visible (allowed OR hint is "disabled") */
  visible: ComputedRef<boolean>
}

// Reasons that indicate a temporary or situational block — the user has
// permission in principle but something else prevents the action right now.
// These are shown as disabled controls with an explanation, not hidden.
const DISABLED_REASONS = new Set([
  'has_expenses',
  'has_settlements',
  'is_settled',
  'poll_closed',
  'not_attending',
])

function hintForReason(reason: string | undefined): Hint {
  return reason && DISABLED_REASONS.has(reason) ? 'disabled' : 'hidden'
}

/**
 * Reads a single ability from a pool object's `abilities` hash.
 *
 * Deny-by-default: if the ability is missing or the object is undefined,
 * the action is treated as denied and hidden.
 *
 * @example
 *   const event = computed(() => pool.get('event', eventId.value))
 *   const { visible, allowed, reason } = useAbility(event, 'update')
 *
 *   // In template:
 *   // <button v-if="visible" :disabled="!allowed" :title="reason">Edit</button>
 */
export function useAbility(
  objectRef:
    | ComputedRef<{ abilities?: Record<string, AbilityResult> } | undefined>
    | Ref<{ abilities?: Record<string, AbilityResult> } | undefined>,
  abilityName: string
): AbilityCheck {
  const ability = computed(() => objectRef.value?.abilities?.[abilityName])

  const allowed = computed(() => ability.value?.allowed ?? false)
  const reason = computed(() => ability.value?.reason)
  const hint = computed(() => hintForReason(reason.value))
  const visible = computed(() => allowed.value || hint.value === 'disabled')

  return { allowed, reason, hint, visible }
}
