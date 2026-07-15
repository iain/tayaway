// Flavor text for the birthday countdown, in the spirit of a game's loading
// screen: the birthday is "being loaded", and these are the little tasks it's
// pretending to work through while you wait. Present-progressive, playful, and
// safe for any audience. Order doesn't matter — the picker hashes into this
// list — but keep it long enough that a card rarely shows the same line twice
// in a row as it rotates.
export const BIRTHDAY_LOADING_PHRASES: readonly string[] = [
  'Warming up the oven…',
  'Whisking the batter…',
  'Sifting 100% pure sprinkles…',
  'Downloading candles…',
  'Rendering confetti…',
  'Compiling birthday wishes…',
  'Inflating the balloons…',
  'Wrapping the presents…',
  'Chilling the fizzy drinks…',
  'Rehearsing the song…',
  'Buffering the surprise…',
  'Calibrating the party hats…',
  'Untangling the streamers…',
  'Applying extra frosting…',
  'Tuning the kazoos…',
  'Reticulating the piñata…',
]

// Small, dependency-free string hash (djb2). Deterministic so a given seed
// always maps to the same phrase — which keeps rendering pure (no `Math.random`
// mid-render) and makes the rotation trivially testable.
function hashString(input: string): number {
  let hash = 5381
  for (let i = 0; i < input.length; i++) {
    hash = (hash * 33) ^ input.charCodeAt(i)
  }
  // `>>> 0` folds the 32-bit signed result into a non-negative integer.
  return hash >>> 0
}

/**
 * Picks a loading phrase for a given seed. Callers build the seed from a stable
 * key plus a time bucket — e.g. `${memberId}:${rotationBucket}` — so each card
 * shows a different phrase from its neighbours and cycles as time passes, all
 * without any shared mutable state.
 */
export function pickBirthdayPhrase(seed: string): string {
  return BIRTHDAY_LOADING_PHRASES[
    hashString(seed) % BIRTHDAY_LOADING_PHRASES.length
  ]!
}
