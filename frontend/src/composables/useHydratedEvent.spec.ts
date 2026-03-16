import { describe, it, expect, beforeEach } from "vitest"
import { createPinia, setActivePinia } from "pinia"
import { computed } from "vue"
import { useObjectPoolStore } from "@/stores/objectPool"
import { useHydratedEvent } from "./useHydratedEvent"
import type { ObjectTypeMap } from "@/types/pool"

// --- Factory helpers ---

function makeEvent(
  overrides: Partial<ObjectTypeMap["event"]> = {}
): ObjectTypeMap["event"] {
  return {
    id: "evt-1",
    objectType: "event",
    name: "Test Event",
    description: null,
    startDate: null,
    endDate: null,
    locationName: null,
    latitude: null,
    longitude: null,
    workspaceId: "ws-1",
    userId: "user-1",
    datePollId: null,
    rsvpIds: [],
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...overrides,
  }
}

function makeMember(
  overrides: Partial<ObjectTypeMap["member"]> = {}
): ObjectTypeMap["member"] {
  return {
    id: "mem-1",
    objectType: "member",
    workspaceId: "ws-1",
    userId: "user-1",
    email: "alice@example.com",
    name: "Alice",
    phoneNumber: null,
    birthday: null,
    locationName: null,
    latitude: null,
    longitude: null,
    hasIban: false,
    role: "member",
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...overrides,
  }
}

function makeWorkspace(
  overrides: Partial<ObjectTypeMap["workspace"]> = {}
): ObjectTypeMap["workspace"] {
  return {
    id: "ws-1",
    objectType: "workspace",
    name: "Test Workspace",
    memberIds: ["mem-1"],
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...overrides,
  }
}

function makeDatePoll(
  overrides: Partial<ObjectTypeMap["datePoll"]> = {}
): ObjectTypeMap["datePoll"] {
  return {
    id: "poll-1",
    objectType: "datePoll",
    eventId: "evt-1",
    deadline: "2026-02-01T00:00:00.000Z",
    selectedDateRangeId: null,
    closedAt: null,
    status: "open",
    dateRangeIds: [],
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...overrides,
  }
}

function makeDateRange(
  overrides: Partial<ObjectTypeMap["dateRange"]> = {}
): ObjectTypeMap["dateRange"] {
  return {
    id: "dr-1",
    objectType: "dateRange",
    datePollId: "poll-1",
    startDate: "2026-03-01",
    endDate: "2026-03-05",
    voteIds: [],
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...overrides,
  }
}

function makeVote(
  overrides: Partial<ObjectTypeMap["vote"]> = {}
): ObjectTypeMap["vote"] {
  return {
    id: "vote-1",
    objectType: "vote",
    dateRangeId: "dr-1",
    userId: "user-1",
    response: "yes",
    comment: null,
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...overrides,
  }
}

function makeRsvp(
  overrides: Partial<ObjectTypeMap["rsvp"]> = {}
): ObjectTypeMap["rsvp"] {
  return {
    id: "rsvp-1",
    objectType: "rsvp",
    eventId: "evt-1",
    userId: "user-1",
    attending: true,
    startDate: null,
    endDate: null,
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...overrides,
  }
}

describe("useHydratedEvent", () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  describe("basic event hydration", () => {
    it("returns undefined for a missing event", () => {
      const { event } = useHydratedEvent("nonexistent")

      expect(event.value).toBeUndefined()
    })

    it("reports isLoading when the event is not in the pool", () => {
      const { isLoading } = useHydratedEvent("nonexistent")

      expect(isLoading.value).toBe(true)
    })

    it("hydrates a basic event from the pool", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()])

      const { event, isLoading } = useHydratedEvent("evt-1")

      expect(isLoading.value).toBe(false)
      expect(event.value).toBeDefined()
      expect(event.value!.id).toBe("evt-1")
      expect(event.value!.name).toBe("Test Event")
      expect(event.value!.workspaceId).toBe("ws-1")
      expect(event.value!.userId).toBe("user-1")
    })

    it("copies all scalar fields from the pool event", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({
          description: "A fun trip",
          startDate: "2026-03-01",
          endDate: "2026-03-05",
          locationName: "Beach House",
          latitude: 52.37,
          longitude: 4.89,
        }),
      ])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.description).toBe("A fun trip")
      expect(event.value!.startDate).toBe("2026-03-01")
      expect(event.value!.endDate).toBe("2026-03-05")
      expect(event.value!.locationName).toBe("Beach House")
      expect(event.value!.latitude).toBe(52.37)
      expect(event.value!.longitude).toBe(4.89)
    })

    it("accepts a ComputedRef as eventId", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()])

      const eventId = computed(() => "evt-1")
      const { event } = useHydratedEvent(eventId)

      expect(event.value).toBeDefined()
      expect(event.value!.id).toBe("evt-1")
    })
  })

  describe("member resolution", () => {
    it("resolves the event creator member by userId", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent(), makeMember()])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.member).toBeDefined()
      expect(event.value!.member!.userId).toBe("user-1")
      expect(event.value!.member!.name).toBe("Alice")
    })

    it("returns undefined member when the member is not in the pool", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ userId: "unknown-user" })])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.member).toBeUndefined()
    })
  })

  describe("workspace hydration", () => {
    it("hydrates the workspace with its members", () => {
      const pool = useObjectPoolStore()
      const member1 = makeMember({ id: "mem-1", userId: "user-1" })
      const member2 = makeMember({
        id: "mem-2",
        userId: "user-2",
        email: "bob@example.com",
        name: "Bob",
        role: "admin",
      })
      pool.importObjects([
        makeEvent(),
        makeWorkspace({ memberIds: ["mem-1", "mem-2"] }),
        member1,
        member2,
      ])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.workspace).toBeDefined()
      expect(event.value!.workspace!.id).toBe("ws-1")
      expect(event.value!.workspace!.name).toBe("Test Workspace")
      expect(event.value!.workspace!.members).toHaveLength(2)
      expect(event.value!.workspace!.members[0]!.email).toBe(
        "alice@example.com"
      )
      expect(event.value!.workspace!.members[1]!.role).toBe("admin")
    })

    it("returns undefined workspace when workspace is not in the pool", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ workspaceId: "missing-ws" })])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.workspace).toBeUndefined()
    })
  })

  describe("date poll hydration", () => {
    it("returns null datePoll when no poll exists", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.datePoll).toBeNull()
    })

    it("hydrates a date poll with its date ranges", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ datePollId: "poll-1" }),
        makeDatePoll({ dateRangeIds: ["dr-1", "dr-2"] }),
        makeDateRange({ id: "dr-1", startDate: "2026-03-01", endDate: "2026-03-05" }),
        makeDateRange({ id: "dr-2", startDate: "2026-03-10", endDate: "2026-03-15" }),
      ])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.datePoll).toBeDefined()
      expect(event.value!.datePoll!.id).toBe("poll-1")
      expect(event.value!.datePoll!.eventId).toBe("evt-1")
      expect(event.value!.datePoll!.status).toBe("open")
      expect(event.value!.datePoll!.dateRanges).toHaveLength(2)
    })

    it("sorts date ranges by startDate", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ datePollId: "poll-1" }),
        makeDatePoll({ dateRangeIds: ["dr-1", "dr-2"] }),
        makeDateRange({ id: "dr-1", startDate: "2026-04-01", endDate: "2026-04-05" }),
        makeDateRange({ id: "dr-2", startDate: "2026-03-01", endDate: "2026-03-05" }),
      ])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.datePoll!.dateRanges[0]!.startDate).toBe("2026-03-01")
      expect(event.value!.datePoll!.dateRanges[1]!.startDate).toBe("2026-04-01")
    })

    it("resolves selectedDateRange when poll has a selected date range", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ datePollId: "poll-1" }),
        makeDatePoll({
          selectedDateRangeId: "dr-2",
          status: "resolved",
          closedAt: "2026-01-15T00:00:00.000Z",
          dateRangeIds: ["dr-1", "dr-2"],
        }),
        makeDateRange({ id: "dr-1", startDate: "2026-03-01", endDate: "2026-03-05" }),
        makeDateRange({ id: "dr-2", startDate: "2026-03-10", endDate: "2026-03-15" }),
      ])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.datePoll!.selectedDateRangeId).toBe("dr-2")
      expect(event.value!.datePoll!.selectedDateRange).toBeDefined()
      expect(event.value!.datePoll!.selectedDateRange!.id).toBe("dr-2")
      expect(event.value!.datePoll!.selectedDateRange!.startDate).toBe("2026-03-10")
    })

    it("returns undefined selectedDateRange when no date range is selected", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ datePollId: "poll-1" }),
        makeDatePoll(),
      ])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.datePoll!.selectedDateRange).toBeUndefined()
    })
  })

  describe("vote hydration", () => {
    it("hydrates votes onto their date ranges", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ datePollId: "poll-1" }),
        makeDatePoll({ dateRangeIds: ["dr-1"] }),
        makeDateRange({ voteIds: ["vote-1", "vote-2"] }),
        makeVote({ id: "vote-1", userId: "user-1", response: "yes" }),
        makeVote({ id: "vote-2", userId: "user-2", response: "no" }),
        makeMember({ id: "mem-1", userId: "user-1", name: "Alice" }),
        makeMember({ id: "mem-2", userId: "user-2", name: "Bob" }),
      ])

      const { event } = useHydratedEvent("evt-1")
      const dateRange = event.value!.datePoll!.dateRanges[0]!

      expect(dateRange.votes).toHaveLength(2)
      expect(dateRange.votes[0]!.response).toBe("yes")
      expect(dateRange.votes[1]!.response).toBe("no")
    })

    it("resolves member on each vote", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ datePollId: "poll-1" }),
        makeDatePoll({ dateRangeIds: ["dr-1"] }),
        makeDateRange({ voteIds: ["vote-1"] }),
        makeVote({ userId: "user-1" }),
        makeMember({ userId: "user-1", name: "Alice" }),
      ])

      const { event } = useHydratedEvent("evt-1")
      const vote = event.value!.datePoll!.dateRanges[0]!.votes[0]!

      expect(vote.member).toBeDefined()
      expect(vote.member!.name).toBe("Alice")
    })

    it("returns undefined member on vote when member is missing", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ datePollId: "poll-1" }),
        makeDatePoll({ dateRangeIds: ["dr-1"] }),
        makeDateRange({ voteIds: ["vote-1"] }),
        makeVote({ userId: "unknown-user" }),
      ])

      const { event } = useHydratedEvent("evt-1")
      const vote = event.value!.datePoll!.dateRanges[0]!.votes[0]!

      expect(vote.member).toBeUndefined()
    })

    it("includes vote comment", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ datePollId: "poll-1" }),
        makeDatePoll({ dateRangeIds: ["dr-1"] }),
        makeDateRange({ voteIds: ["vote-1"] }),
        makeVote({ comment: "Works for me!" }),
      ])

      const { event } = useHydratedEvent("evt-1")
      const vote = event.value!.datePoll!.dateRanges[0]!.votes[0]!

      expect(vote.comment).toBe("Works for me!")
    })
  })

  describe("vote summary calculation", () => {
    it("calculates vote summary for a date range", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ datePollId: "poll-1" }),
        makeDatePoll({ dateRangeIds: ["dr-1"] }),
        makeDateRange({ voteIds: ["v1", "v2", "v3", "v4"] }),
        makeVote({ id: "v1", userId: "u1", response: "yes" }),
        makeVote({ id: "v2", userId: "u2", response: "yes" }),
        makeVote({ id: "v3", userId: "u3", response: "no" }),
        makeVote({ id: "v4", userId: "u4", response: "preferably_not" }),
      ])

      const { event } = useHydratedEvent("evt-1")
      const summary = event.value!.datePoll!.dateRanges[0]!.voteSummary

      expect(summary.yes).toBe(2)
      expect(summary.no).toBe(1)
      expect(summary.preferably_not).toBe(1)
      expect(summary.total).toBe(4)
    })

    it("returns zero counts when no votes exist", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ datePollId: "poll-1" }),
        makeDatePoll({ dateRangeIds: ["dr-1"] }),
        makeDateRange(),
      ])

      const { event } = useHydratedEvent("evt-1")
      const summary = event.value!.datePoll!.dateRanges[0]!.voteSummary

      expect(summary.yes).toBe(0)
      expect(summary.no).toBe(0)
      expect(summary.preferably_not).toBe(0)
      expect(summary.total).toBe(0)
    })
  })

  describe("RSVP hydration", () => {
    it("hydrates RSVPs for the event", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ rsvpIds: ["rsvp-1", "rsvp-2"] }),
        makeRsvp({ id: "rsvp-1", userId: "user-1", attending: true }),
        makeRsvp({ id: "rsvp-2", userId: "user-2", attending: false }),
        makeMember({ id: "mem-1", userId: "user-1", name: "Alice" }),
        makeMember({ id: "mem-2", userId: "user-2", name: "Bob" }),
      ])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.rsvps).toHaveLength(2)
      expect(event.value!.rsvps[0]!.attending).toBe(true)
      expect(event.value!.rsvps[0]!.member).toBeDefined()
      expect(event.value!.rsvps[0]!.member!.name).toBe("Alice")
      expect(event.value!.rsvps[1]!.attending).toBe(false)
      expect(event.value!.rsvps[1]!.member!.name).toBe("Bob")
    })

    it("includes RSVP date range fields", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ rsvpIds: ["rsvp-1"] }),
        makeRsvp({
          startDate: "2026-03-01",
          endDate: "2026-03-05",
        }),
      ])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.rsvps[0]!.startDate).toBe("2026-03-01")
      expect(event.value!.rsvps[0]!.endDate).toBe("2026-03-05")
    })

    it("returns empty rsvps array when no RSVPs exist", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent()])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.rsvps).toEqual([])
    })

    it("only includes RSVPs for the specific event", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ id: "evt-1", rsvpIds: ["rsvp-1"] }),
        makeRsvp({ id: "rsvp-1", eventId: "evt-1" }),
        makeRsvp({ id: "rsvp-2", eventId: "evt-other" }),
      ])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.rsvps).toHaveLength(1)
      expect(event.value!.rsvps[0]!.id).toBe("rsvp-1")
    })
  })

  describe("cross-event isolation", () => {
    it("only includes date ranges belonging to the event poll", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ id: "evt-1", datePollId: "poll-1" }),
        makeDatePoll({ id: "poll-1", eventId: "evt-1", dateRangeIds: ["dr-1"] }),
        makeDateRange({ id: "dr-1", datePollId: "poll-1" }),
        makeDateRange({ id: "dr-other", datePollId: "poll-other" }),
      ])

      const { event } = useHydratedEvent("evt-1")

      expect(event.value!.datePoll!.dateRanges).toHaveLength(1)
      expect(event.value!.datePoll!.dateRanges[0]!.id).toBe("dr-1")
    })

    it("only includes votes belonging to the event date ranges", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeEvent({ id: "evt-1", datePollId: "poll-1" }),
        makeDatePoll({ id: "poll-1", eventId: "evt-1", dateRangeIds: ["dr-1"] }),
        makeDateRange({ id: "dr-1", datePollId: "poll-1", voteIds: ["v1"] }),
        makeVote({ id: "v1", dateRangeId: "dr-1" }),
        makeVote({ id: "v-other", dateRangeId: "dr-other" }),
      ])

      const { event } = useHydratedEvent("evt-1")

      const votes = event.value!.datePoll!.dateRanges[0]!.votes
      expect(votes).toHaveLength(1)
      expect(votes[0]!.id).toBe("v1")
    })
  })

  describe("reactivity", () => {
    it("updates when pool data changes", () => {
      const pool = useObjectPoolStore()
      pool.importObjects([makeEvent({ name: "Original" })])

      const { event } = useHydratedEvent("evt-1")
      expect(event.value!.name).toBe("Original")

      pool.importObjects([
        makeEvent({ name: "Updated", updatedAt: "2026-02-01T00:00:00.000Z" }),
      ])
      expect(event.value!.name).toBe("Updated")
    })

    it("becomes defined when event is added to pool", () => {
      const pool = useObjectPoolStore()
      const { event, isLoading } = useHydratedEvent("evt-1")

      expect(event.value).toBeUndefined()
      expect(isLoading.value).toBe(true)

      pool.importObjects([makeEvent()])

      expect(event.value).toBeDefined()
      expect(isLoading.value).toBe(false)
    })
  })
})
