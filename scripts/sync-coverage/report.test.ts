import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { buildReport, formatReport, parseSpec, readPlaywright, readRspec, readVitest } from './report.ts'
import type { SpecEntry, TestResult } from './report.ts'

describe('parseSpec', () => {
  it('finds principles, guarantees and scenarios defined by headings', () => {
    const markdown = [
      '#### SYNC-P-1: The network is optional',
      'Body text mentioning SYNC-G-999 inline.',
      '#### SYNC-G-302: Catch-up sync misses nothing',
      '#### SYNC-S-001: Shopping without signal',
    ].join('\n')

    assert.deepEqual(parseSpec(markdown), [
      { id: 'SYNC-P-1', kind: 'principle', title: 'The network is optional', retired: false },
      { id: 'SYNC-G-302', kind: 'guarantee', title: 'Catch-up sync misses nothing', retired: false },
      { id: 'SYNC-S-001', kind: 'scenario', title: 'Shopping without signal', retired: false },
    ])
  })

  it('marks an entry retired when its section says so', () => {
    const markdown = [
      '#### SYNC-G-101: Old guarantee',
      '',
      'Status: retired. Replaced by SYNC-G-102.',
      '#### SYNC-G-102: New guarantee',
      'Mentions Status: retired only in passing.',
    ].join('\n')

    assert.deepEqual(
      parseSpec(markdown).map((entry) => [entry.id, entry.retired]),
      [
        ['SYNC-G-101', true],
        ['SYNC-G-102', false],
      ],
    )
  })
})

describe('readVitest', () => {
  it('reads tagged IDs and outcomes, treating the known-gap tag as an expected failure', () => {
    const json = {
      testResults: [
        {
          assertionResults: [
            { fullName: '[SYNC-G-101] queue [SYNC-G-102] survives reload', status: 'passed', tags: [] },
            { fullName: '[SYNC-G-403] clears pending on confirmation', status: 'passed', tags: ['known-gap'] },
            { fullName: '[SYNC-G-404] fixed but still marked', status: 'failed', tags: ['known-gap'] },
            { fullName: 'untagged test', status: 'passed', tags: [] },
            { fullName: '[SYNC-G-105] skipped', status: 'skipped', tags: [] },
          ],
        },
      ],
    }

    assert.deepEqual(readVitest(json), [
      { runner: 'vitest', name: '[SYNC-G-101] queue [SYNC-G-102] survives reload', ids: ['SYNC-G-101', 'SYNC-G-102'], outcome: 'passed' },
      { runner: 'vitest', name: '[SYNC-G-403] clears pending on confirmation', ids: ['SYNC-G-403'], outcome: 'known-gap' },
      { runner: 'vitest', name: '[SYNC-G-404] fixed but still marked', ids: ['SYNC-G-404'], outcome: 'failed' },
      { runner: 'vitest', name: '[SYNC-G-105] skipped', ids: ['SYNC-G-105'], outcome: 'skipped' },
    ])
  })
})

describe('readRspec', () => {
  it('reads tagged IDs and outcomes, treating a "Known gap" pending as an expected failure', () => {
    const json = {
      examples: [
        { full_description: 'Sync [SYNC-G-302] returns rows committed late', status: 'passed', pending_message: null },
        { full_description: '[SYNC-G-309] resets on unknown cursor', status: 'pending', pending_message: 'Known gap' },
        { full_description: '[SYNC-G-310] temporarily skipped', status: 'pending', pending_message: 'Temporarily skipped with xit' },
        { full_description: '[SYNC-G-311] broken', status: 'failed', pending_message: null },
        { full_description: 'untagged', status: 'passed', pending_message: null },
      ],
    }

    assert.deepEqual(readRspec(json), [
      { runner: 'rspec', name: 'Sync [SYNC-G-302] returns rows committed late', ids: ['SYNC-G-302'], outcome: 'passed' },
      { runner: 'rspec', name: '[SYNC-G-309] resets on unknown cursor', ids: ['SYNC-G-309'], outcome: 'known-gap' },
      { runner: 'rspec', name: '[SYNC-G-310] temporarily skipped', ids: ['SYNC-G-310'], outcome: 'skipped' },
      { runner: 'rspec', name: '[SYNC-G-311] broken', ids: ['SYNC-G-311'], outcome: 'failed' },
    ])
  })
})

describe('readPlaywright', () => {
  it('reads IDs from nested titles and tags, treating test.fail() as an expected failure', () => {
    const json = {
      suites: [
        {
          title: 'shopping.spec.ts',
          specs: [],
          suites: [
            {
              title: '[SYNC-S-001] Shopping without signal',
              specs: [
                { title: 'combines both lists', tags: ['SYNC-G-503'], tests: [{ expectedStatus: 'passed', status: 'expected' }] },
                { title: '[SYNC-G-404] known gap', tags: [], tests: [{ expectedStatus: 'failed', status: 'expected' }] },
                { title: '[SYNC-G-405] fixed gap', tags: [], tests: [{ expectedStatus: 'failed', status: 'unexpected' }] },
                { title: '[SYNC-G-406] retried', tags: [], tests: [{ expectedStatus: 'passed', status: 'flaky' }] },
                { title: '[SYNC-G-407] skipped', tags: [], tests: [{ expectedStatus: 'skipped', status: 'skipped' }] },
              ],
            },
          ],
        },
      ],
    }

    assert.deepEqual(readPlaywright(json), [
      { runner: 'playwright', name: '[SYNC-S-001] Shopping without signal combines both lists', ids: ['SYNC-S-001', 'SYNC-G-503'], outcome: 'passed' },
      { runner: 'playwright', name: '[SYNC-S-001] Shopping without signal [SYNC-G-404] known gap', ids: ['SYNC-S-001', 'SYNC-G-404'], outcome: 'known-gap' },
      { runner: 'playwright', name: '[SYNC-S-001] Shopping without signal [SYNC-G-405] fixed gap', ids: ['SYNC-S-001', 'SYNC-G-405'], outcome: 'failed' },
      { runner: 'playwright', name: '[SYNC-S-001] Shopping without signal [SYNC-G-406] retried', ids: ['SYNC-S-001', 'SYNC-G-406'], outcome: 'passed' },
      { runner: 'playwright', name: '[SYNC-S-001] Shopping without signal [SYNC-G-407] skipped', ids: ['SYNC-S-001', 'SYNC-G-407'], outcome: 'skipped' },
    ])
  })
})

function guarantee(id: string): SpecEntry {
  return { id, kind: 'guarantee', title: `Title of ${id}`, retired: false }
}

function result(ids: string[], outcome: TestResult['outcome'], runner: TestResult['runner'] = 'vitest'): TestResult {
  return { runner, name: `test of ${ids.join(' ')}`, ids, outcome }
}

describe('buildReport', () => {
  it('gives each guarantee one status: failing over known gap over covered over uncovered', () => {
    const spec = ['SYNC-G-101', 'SYNC-G-102', 'SYNC-G-103', 'SYNC-G-104', 'SYNC-G-105'].map(guarantee)
    const results = [
      result(['SYNC-G-101'], 'passed'),
      result(['SYNC-G-102'], 'passed'),
      result(['SYNC-G-102'], 'known-gap'),
      result(['SYNC-G-103'], 'known-gap'),
      result(['SYNC-G-103'], 'failed'),
      result(['SYNC-G-104'], 'skipped'),
    ]

    const statuses = buildReport(spec, results).entries.map((entry) => [entry.id, entry.status])

    assert.deepEqual(statuses, [
      ['SYNC-G-101', 'covered'],
      ['SYNC-G-102', 'known-gap'],
      ['SYNC-G-103', 'failing'],
      ['SYNC-G-104', 'uncovered'],
      ['SYNC-G-105', 'uncovered'],
    ])
  })
  it('counts only end-to-end tests for scenarios and reports scenario tags elsewhere', () => {
    const spec: SpecEntry[] = [{ id: 'SYNC-S-001', kind: 'scenario', title: 'Shopping', retired: false }]
    const results = [result(['SYNC-S-001'], 'failed', 'vitest'), result(['SYNC-S-001'], 'known-gap', 'playwright')]

    const report = buildReport(spec, results)

    assert.deepEqual(
      report.entries.map((entry) => [entry.id, entry.status]),
      [['SYNC-S-001', 'known-gap']],
    )
    assert.deepEqual(report.errors, [
      'test of SYNC-S-001 (vitest): scenario SYNC-S-001 can only be covered by an end-to-end test',
    ])
  })
  it('reports tags that point at unknown, retired or principle IDs', () => {
    const spec: SpecEntry[] = [
      { id: 'SYNC-P-7', kind: 'principle', title: 'Order from the server', retired: false },
      { id: 'SYNC-G-101', kind: 'guarantee', title: 'Old', retired: true },
    ]
    const results = [result(['SYNC-G-999', 'SYNC-G-101', 'SYNC-P-7'], 'passed')]

    assert.deepEqual(buildReport(spec, results).errors, [
      'test of SYNC-G-999 SYNC-G-101 SYNC-P-7 (vitest): SYNC-G-999 is not defined in the spec',
      'test of SYNC-G-999 SYNC-G-101 SYNC-P-7 (vitest): SYNC-G-101 is retired',
      'test of SYNC-G-999 SYNC-G-101 SYNC-P-7 (vitest): principle SYNC-P-7 is not a coverage target; tag the guarantees that realise it',
    ])
  })
})

describe('formatReport', () => {
  it('summarises counts, lists IDs per status with their tests, and lists errors', () => {
    const spec = ['SYNC-G-101', 'SYNC-G-102', 'SYNC-G-103'].map(guarantee)
    const results = [
      result(['SYNC-G-101'], 'passed'),
      result(['SYNC-G-102'], 'known-gap', 'rspec'),
      result(['SYNC-G-999'], 'passed'),
    ]

    assert.equal(
      formatReport(buildReport(spec, results)),
      [
        '# Sync Engine v2 coverage',
        '',
        '| Status | Count |',
        '|---|---|',
        '| Failing | 0 |',
        '| Known gap | 1 |',
        '| Covered | 1 |',
        '| Uncovered | 1 |',
        '',
        '## Known gap',
        '',
        '- **SYNC-G-102** Title of SYNC-G-102',
        '  - test of SYNC-G-102 (rspec)',
        '',
        '## Covered',
        '',
        '- **SYNC-G-101** Title of SYNC-G-101',
        '  - test of SYNC-G-101 (vitest)',
        '',
        '## Uncovered',
        '',
        '- **SYNC-G-103** Title of SYNC-G-103',
        '',
        '## Errors',
        '',
        '- test of SYNC-G-999 (vitest): SYNC-G-999 is not defined in the spec',
        '',
      ].join('\n'),
    )
  })
})
