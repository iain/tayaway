import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { parseSpec, readPlaywright, readRspec, readVitest } from './report.ts'

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
