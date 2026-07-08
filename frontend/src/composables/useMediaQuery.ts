import { onScopeDispose, ref, type Ref } from 'vue'

// Reactive wrapper around `window.matchMedia`. Returns a ref that tracks whether
// the query currently matches and updates as the viewport changes.
//
// Reach for this when two layouts are structurally different enough that
// reflowing one with CSS would be a hack, e.g. the chore roster's desktop grid
// (dates x chores) vs. its mobile day-first list. Rendering exactly one of them
// via `v-if` also keeps text selectors unique for the e2e suite, which a
// CSS `hidden` toggle (both trees in the DOM) would not.
export function useMediaQuery(query: string): Ref<boolean> {
  const mql = window.matchMedia(query)
  const matches = ref(mql.matches)

  function update(event: MediaQueryListEvent): void {
    matches.value = event.matches
  }

  mql.addEventListener('change', update)
  onScopeDispose(() => mql.removeEventListener('change', update))

  return matches
}
