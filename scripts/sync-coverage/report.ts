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

export type Status = 'covered' | 'known-gap' | 'failing' | 'uncovered'

export type ReportEntry = SpecEntry & { status: Status; tests: TestResult[] }

export type Report = { entries: ReportEntry[]; errors: string[] }

function statusOf(tests: TestResult[]): Status {
  const outcomes = new Set(tests.map((test) => test.outcome))
  if (outcomes.has('failed')) {
    return 'failing'
  } else if (outcomes.has('known-gap')) {
    return 'known-gap'
  } else if (outcomes.has('passed')) {
    return 'covered'
  } else {
    return 'uncovered'
  }
}

// A scenario is a user-visible flow, so only an end-to-end test can show it works.
function counts(entry: SpecEntry, result: TestResult): boolean {
  if (entry.kind === 'scenario') {
    return result.runner === 'playwright'
  } else {
    return true
  }
}

function tagErrors(spec: SpecEntry[], result: TestResult): string[] {
  const where = `${result.name} (${result.runner})`
  return result.ids.flatMap((id) => {
    const entry = spec.find((candidate) => candidate.id === id)
    if (!entry) {
      return [`${where}: ${id} is not defined in the spec`]
    } else if (entry.retired) {
      return [`${where}: ${id} is retired`]
    } else if (entry.kind === 'principle') {
      return [`${where}: principle ${id} is not a coverage target; tag the guarantees that realise it`]
    } else if (!counts(entry, result)) {
      return [`${where}: scenario ${id} can only be covered by an end-to-end test`]
    } else {
      return []
    }
  })
}

export function buildReport(spec: SpecEntry[], results: TestResult[]): Report {
  const entries = spec
    .filter((entry) => entry.kind !== 'principle' && !entry.retired)
    .map((entry) => {
      const tests = results.filter((result) => result.ids.includes(entry.id) && counts(entry, result))
      return { ...entry, status: statusOf(tests), tests }
    })
  const errors = results.flatMap((result) => tagErrors(spec, result))
  return { entries, errors }
}

const STATUS_LABELS: [Status, string][] = [
  ['failing', 'Failing'],
  ['known-gap', 'Known gap'],
  ['covered', 'Covered'],
  ['uncovered', 'Uncovered'],
]

function formatEntry(entry: ReportEntry): string[] {
  const heading = `- **${entry.id}** ${entry.title}`
  const tests = entry.tests.map((test) => `  - ${test.name} (${test.runner})`)
  return [heading, ...tests]
}

export function formatReport(report: Report): string {
  const lines = ['# Sync Engine v2 coverage', '', '| Status | Count |', '|---|---|']
  for (const [status, label] of STATUS_LABELS) {
    const count = report.entries.filter((entry) => entry.status === status).length
    lines.push(`| ${label} | ${count} |`)
  }
  lines.push('')

  for (const [status, label] of STATUS_LABELS) {
    const entries = report.entries.filter((entry) => entry.status === status)
    if (entries.length > 0) {
      lines.push(`## ${label}`, '', ...entries.flatMap(formatEntry), '')
    }
  }

  if (report.errors.length > 0) {
    lines.push('## Errors', '', ...report.errors.map((error) => `- ${error}`), '')
  }
  return lines.join('\n')
}
