export type SpecEntry = {
  id: string
  kind: 'principle' | 'guarantee' | 'scenario'
  title: string
  retired: boolean
}

const HEADING = /^#### (SYNC-([PGS])-\d+): (.+)$/
const RETIRED = /^Status: retired\b/

const KINDS = {
  P: 'principle',
  G: 'guarantee',
  S: 'scenario',
} as const

export function parseSpec(markdown: string): SpecEntry[] {
  const entries: SpecEntry[] = []
  for (const line of markdown.split('\n')) {
    const match = HEADING.exec(line)
    const current = entries.at(-1)
    if (match) {
      const [, id, letter, title] = match
      entries.push({ id, kind: KINDS[letter as keyof typeof KINDS], title, retired: false })
    } else if (current && RETIRED.test(line)) {
      current.retired = true
    }
  }
  return entries
}

export type Outcome = 'passed' | 'known-gap' | 'failed' | 'skipped'

export type TestResult = {
  runner: 'rspec' | 'vitest' | 'playwright'
  name: string
  ids: string[]
  outcome: Outcome
}

const TAGGED_ID = /SYNC-[PGS]-\d+/g

export function idsIn(name: string): string[] {
  return [...new Set(name.match(TAGGED_ID) ?? [])]
}

type VitestJson = {
  testResults: {
    assertionResults: { fullName: string; status: string; tags?: string[] }[]
  }[]
}

// A test tagged `known-gap` runs with `fails: true` (see frontend/vitest.config.ts),
// so Vitest reports it as passed while the gap is still there.
function vitestOutcome(status: string, tags: string[]): Outcome {
  if (status === 'failed') {
    return 'failed'
  } else if (status === 'passed' && tags.includes('known-gap')) {
    return 'known-gap'
  } else if (status === 'passed') {
    return 'passed'
  } else {
    return 'skipped'
  }
}

export function readVitest(json: VitestJson): TestResult[] {
  return json.testResults
    .flatMap((file) => file.assertionResults)
    .map((test) => ({
      runner: 'vitest' as const,
      name: test.fullName,
      ids: idsIn(test.fullName),
      outcome: vitestOutcome(test.status, test.tags ?? []),
    }))
    .filter((result) => result.ids.length > 0)
}

type RspecJson = {
  examples: { full_description: string; status: string; pending_message: string | null }[]
}

// `known_gap: true` metadata becomes `pending: "Known gap"` (see backend/spec/support/sync_coverage.rb):
// RSpec runs the example and reports it as pending only while it still fails.
export const RSPEC_KNOWN_GAP_MESSAGE = 'Known gap'

function rspecOutcome(status: string, pendingMessage: string | null): Outcome {
  if (status === 'passed') {
    return 'passed'
  } else if (status === 'failed') {
    return 'failed'
  } else if (pendingMessage === RSPEC_KNOWN_GAP_MESSAGE) {
    return 'known-gap'
  } else {
    return 'skipped'
  }
}

export function readRspec(json: RspecJson): TestResult[] {
  return json.examples
    .map((example) => ({
      runner: 'rspec' as const,
      name: example.full_description,
      ids: idsIn(example.full_description),
      outcome: rspecOutcome(example.status, example.pending_message),
    }))
    .filter((result) => result.ids.length > 0)
}

type PlaywrightTest = { expectedStatus: string; status: string }
type PlaywrightSpec = { title: string; tags: string[]; tests: PlaywrightTest[] }
type PlaywrightSuite = { title: string; specs?: PlaywrightSpec[]; suites?: PlaywrightSuite[] }
type PlaywrightJson = { suites: PlaywrightSuite[] }

// `test.fail()` sets expectedStatus to "failed"; status "expected" then means it still fails.
function playwrightOutcome(test: PlaywrightTest): Outcome {
  if (test.status === 'unexpected') {
    return 'failed'
  } else if (test.status === 'skipped') {
    return 'skipped'
  } else if (test.expectedStatus === 'failed') {
    return 'known-gap'
  } else {
    return 'passed'
  }
}

// The top-level suites are files; their titles are paths, not part of the test name.
function playwrightSpecs(suite: PlaywrightSuite, titles: string[]): TestResult[] {
  const own = (suite.specs ?? []).flatMap((spec) => {
    const name = [...titles, spec.title].join(' ')
    return spec.tests.map((test) => ({
      runner: 'playwright' as const,
      name,
      ids: [...new Set([...idsIn(name), ...spec.tags.flatMap(idsIn)])],
      outcome: playwrightOutcome(test),
    }))
  })
  const nested = (suite.suites ?? []).flatMap((child) => playwrightSpecs(child, [...titles, child.title]))
  return [...own, ...nested]
}

export function readPlaywright(json: PlaywrightJson): TestResult[] {
  return json.suites
    .flatMap((file) => playwrightSpecs(file, []))
    .filter((result) => result.ids.length > 0)
}
