// Prints the Sync Engine v2 coverage report: every guarantee and scenario in
// doc/sync/spec.md with its status, based on the latest results each test
// runner wrote to tmp/sync-coverage/. Exits non-zero when a test is tagged
// with an ID it may not use. See doc/sync/roadmap.md.
import { existsSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { buildReport, formatReport, parseSpec, readPlaywright, readRspec, readVitest } from './report.ts'
import type { TestResult } from './report.ts'

const root = fileURLToPath(new URL('../../', import.meta.url))

const SOURCES = [
  { file: 'rspec.json', read: readRspec, command: "mise run '//backend:test'" },
  { file: 'vitest.json', read: readVitest, command: "mise run '//frontend:test'" },
  { file: 'playwright.json', read: readPlaywright, command: 'mise run e2e' },
]

const spec = parseSpec(readFileSync(`${root}doc/sync/spec.md`, 'utf8'))
const results: TestResult[] = []
const missing: string[] = []

for (const source of SOURCES) {
  const path = `${root}tmp/sync-coverage/${source.file}`
  if (existsSync(path)) {
    results.push(...source.read(JSON.parse(readFileSync(path, 'utf8'))))
  } else {
    missing.push(`- No ${source.file} yet: run \`${source.command}\``)
  }
}

const report = buildReport(spec, results)
console.log(formatReport(report))
if (missing.length > 0) {
  console.log(['## Missing results', '', ...missing, ''].join('\n'))
}
process.exitCode = report.errors.length > 0 ? 1 : 0
