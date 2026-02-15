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
    member: { type: 'belongsTo', foreignKey: 'memberId', targetType: 'member' },
    dateRanges: {
      type: 'hasMany',
      foreignKey: 'dateRangeIds',
      targetType: 'dateRange',
    },
  },
  dateRange: {
    event: { type: 'belongsTo', foreignKey: 'eventId', targetType: 'event' },
    votes: { type: 'hasMany', foreignKey: 'voteIds', targetType: 'vote' },
  },
  vote: {
    dateRange: {
      type: 'belongsTo',
      foreignKey: 'dateRangeId',
      targetType: 'dateRange',
    },
    member: { type: 'belongsTo', foreignKey: 'memberId', targetType: 'member' },
  },
} as const
