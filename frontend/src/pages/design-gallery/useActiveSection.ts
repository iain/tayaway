import { onBeforeUnmount, onMounted, ref } from 'vue'
import type { TOCItem } from '@/pages/design-gallery/types'

// IntersectionObserver-driven active-section tracking shared between the
// desktop rail and the mobile chip row. Both TOC variants ship their own
// observer because the alternative (hoisting state to the page and threading
// it through props) doesn't repay the complexity at two callers — but the
// activation rule (rootMargin, biggest-visible-at-top wins) lives in one
// place so the rail and chip row can never drift on which section is active.
//
// `scrollTo` updates `activeId` eagerly so the user's click is reflected
// before the observer's next firing.
export function useActiveSection(items: TOCItem[]): {
  activeId: ReturnType<typeof ref<string | null>>
  scrollTo: (event: MouseEvent, id: string) => void
} {
  const activeId = ref<string | null>(null)
  let observer: IntersectionObserver | null = null

  onMounted(() => {
    observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)
        if (visible[0]) {
          activeId.value = visible[0].target.id
        }
      },
      { rootMargin: '-20% 0px -70% 0px', threshold: 0 }
    )
    for (const item of items) {
      const el = document.getElementById(item.id)
      if (el) observer.observe(el)
    }
  })

  onBeforeUnmount(() => observer?.disconnect())

  function scrollTo(event: MouseEvent, id: string): void {
    const prefersReducedMotion = window.matchMedia(
      '(prefers-reduced-motion: reduce)'
    ).matches
    const target = document.getElementById(id)
    if (!target) return
    event.preventDefault()
    target.scrollIntoView({
      behavior: prefersReducedMotion ? 'auto' : 'smooth',
      block: 'start',
    })
    history.replaceState(null, '', `#${id}`)
    activeId.value = id
  }

  return { activeId, scrollTo }
}
