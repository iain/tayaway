// Relationship schema for pool objects
// Defines how objects relate to each other for denormalization

import type { ObjectType } from './pool'

export interface BelongsToRelation {
  type: 'belongsTo'
  foreignKey: string
  targetType: ObjectType
}

export interface HasManyRelation {
  type: 'hasMany'
  foreignKey: string
  targetType: ObjectType
}

export type Relation = BelongsToRelation | HasManyRelation

export type RelationshipSchema = {
  [K in ObjectType]: Record<string, Relation>
}

export const relationshipSchema: RelationshipSchema = {
  member: {},
  event: {
    member: { type: 'belongsTo', foreignKey: 'userId', targetType: 'member' },
    dateRanges: {
      type: 'hasMany',
      foreignKey: 'dateRangeIds',
      targetType: 'dateRange',
    },
  },
  datePoll: {
    event: { type: 'belongsTo', foreignKey: 'eventId', targetType: 'event' },
    dateRanges: {
      type: 'hasMany',
      foreignKey: 'dateRangeIds',
      targetType: 'dateRange',
    },
  },
  dateRange: {
    event: { type: 'belongsTo', foreignKey: 'eventId', targetType: 'event' },
  },
  vote: {
    dateRange: {
      type: 'belongsTo',
      foreignKey: 'dateRangeId',
      targetType: 'dateRange',
    },
    member: { type: 'belongsTo', foreignKey: 'userId', targetType: 'member' },
  },
  rsvp: {
    event: { type: 'belongsTo', foreignKey: 'eventId', targetType: 'event' },
    member: { type: 'belongsTo', foreignKey: 'userId', targetType: 'member' },
  },
  workspace: {},
  taskList: {
    workspace: {
      type: 'belongsTo',
      foreignKey: 'workspaceId',
      targetType: 'workspace',
    },
  },
  taskItem: {
    taskList: {
      type: 'belongsTo',
      foreignKey: 'taskListId',
      targetType: 'taskList',
    },
  },
  expense: {
    event: { type: 'belongsTo', foreignKey: 'eventId', targetType: 'event' },
    member: { type: 'belongsTo', foreignKey: 'userId', targetType: 'member' },
  },
  settlement: {
    event: { type: 'belongsTo', foreignKey: 'eventId', targetType: 'event' },
    transfers: {
      type: 'hasMany',
      foreignKey: 'transferIds',
      targetType: 'settlementTransfer',
    },
  },
  settlementTransfer: {
    settlement: {
      type: 'belongsTo',
      foreignKey: 'settlementId',
      targetType: 'settlement',
    },
  },
  choreRoster: {
    event: {
      type: 'belongsTo',
      foreignKey: 'eventId',
      targetType: 'event',
    },
    chores: {
      type: 'hasMany',
      foreignKey: 'choreIds',
      targetType: 'chore',
    },
  },
  chore: {
    choreRoster: {
      type: 'belongsTo',
      foreignKey: 'choreRosterId',
      targetType: 'choreRoster',
    },
    assignments: {
      type: 'hasMany',
      foreignKey: 'assignmentIds',
      targetType: 'choreAssignment',
    },
  },
  choreAssignment: {
    chore: {
      type: 'belongsTo',
      foreignKey: 'choreId',
      targetType: 'chore',
    },
    member: {
      type: 'belongsTo',
      foreignKey: 'userId',
      targetType: 'member',
    },
  },
  expenseParticipant: {
    expense: {
      type: 'belongsTo',
      foreignKey: 'expenseId',
      targetType: 'expense',
    },
    member: {
      type: 'belongsTo',
      foreignKey: 'userId',
      targetType: 'member',
    },
  },
  workspaceInvite: {},
} as const
