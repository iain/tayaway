interface Positioned {
  id: string
  position: number
  createdAt: string
}

/**
 * Comparator factory for manually-positioned objects: position, then
 * createdAt, then the object's display label (item content / list name),
 * then id. Position ties happen in practice — two clients adding
 * concurrently both get max + 1, and two drags into the same gap compute
 * the same midpoint — and without a deterministic tie-break each client
 * falls back to its own pool insertion order, so the same list renders in
 * different orders on different devices.
 *
 * Timestamps compare as strings (the serializer emits one uniform ISO-8601
 * format). Labels compare by code unit, not localeCompare: locale-aware
 * collation differs between devices, which would reintroduce exactly the
 * divergence this comparator exists to remove.
 */
export function byPositionOrder<T extends Positioned>(
  labelOf: (item: T) => string
): (a: T, b: T) => number {
  return (a, b) => {
    if (a.position !== b.position) return a.position - b.position
    if (a.createdAt !== b.createdAt) return a.createdAt < b.createdAt ? -1 : 1
    const labelA = labelOf(a)
    const labelB = labelOf(b)
    if (labelA !== labelB) return labelA < labelB ? -1 : 1
    return a.id < b.id ? -1 : 1
  }
}
