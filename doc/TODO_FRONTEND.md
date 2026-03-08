# Frontend Review — TODO

Full codebase audit of `frontend/`. Findings deduplicated across 8 audit dimensions.

## Critical

1. **[Testability] Object pool store has zero unit tests**
   `stores/objectPool.ts` — The central data layer (timestamp merge, pending update overlay, cascade clearing) has no tests. Create `objectPool.spec.ts` covering `importObjects`, `get` with pending overlay, `addPending`/`removePending` lifecycle, and `replaceObjects`.

2. **[Testability] useMutation composable has zero unit tests**
   `composables/useMutation.ts` — The mandatory mutation intermediary (optimistic create/update/destroy, rollback, offline queueing) is untested. Create `useMutation.spec.ts` testing pool state through success, network error (`CommandQueuedError`), and server error scenarios.

## Major

3. **[Correctness] CASCADE_RELATIONS map is incomplete — orphaned objects after delete broadcasts**
   `stores/websocket.ts:57-64` — Only covers `event->datePoll->dateRange->vote` and `taskList->taskItem`. Missing: `event->rsvp`, `event->expense`, `event->settlement`, `event->choreRoster`, `settlement->settlementTransfer`, `choreRoster->chore`, `chore->choreAssignment`. After another user deletes an event, child objects remain as stale data in the pool.

4. **[Reliability] Full sync discards pending optimistic updates for queued commands**
   `stores/objectPool.ts:334-355` — `replaceObjects()` unconditionally clears `pendingUpdates`. If the user made offline changes still in the command queue, optimistic temp objects vanish from the UI until the queued command replays. Preserve pending updates that correspond to unprocessed queue commands.

5. **[Reliability] Optimistic delete does not cascade-remove child objects; rollback only restores parent**
   `composables/useMutation.ts:119-149` — `destroy()` saves/removes only the target object. Child objects remain visible as orphans until the server broadcast triggers `cascadeRemove`. On rollback, only the parent is restored. Have `destroy()` also save and remove cascaded children, or ensure rendering handles orphaned children gracefully.

6. **[Performance] Global `version` counter invalidates all pool consumers on any change**
   `stores/objectPool.ts:100-101` — A single version ref is incremented on every mutation. A task item completion triggers recomputation of event hydration, expense lists, chore grids, etc. Replace with per-type version counters so consumers only recompute when their relevant object types change.

7. **[Performance] Cascading O(N\*M) linear scans in event hydration**
   `composables/useHydratedEvent.ts:117-295` — `findBy('member', 'userId', ...)` is called per vote and per RSVP, each doing a full `getAll` + linear search. For an event with 5 date ranges and 10 voters, this is ~50 full member pool scans per hydration — triggered on every pool version change. Build a `userId->member` Map once at the top, or add a secondary index for `member` by `userId`.

8. **[Observability] No global error handler or error monitoring**
   `main.ts` — No `app.config.errorHandler`, no `window.onerror`, no `unhandledrejection` listener, no Sentry/Bugsnag. Unhandled errors in production are invisible. At minimum, set `app.config.errorHandler` and add a global `unhandledrejection` listener.

9. **[Observability] WebSocket connection failures are completely silent**
   `stores/websocket.ts:132-163` — `onopen`, `onerror`, `onclose` handlers produce zero logging. Repeated connection failures are undiagnosable from the browser console. Add `console.warn` with close codes and reconnect attempt counts.

10. **[Operability] Stale `index.html` served by nginx without cache-control headers**
    `config/deploy/tayaway.nginx.conf:84-87` — The `location /` block has no `Cache-Control` header for HTML files. After deploy, browsers/CDNs can cache stale HTML referencing old hashed asset filenames, breaking the app. Add `Cache-Control: no-cache` for HTML responses.

11. **[Operability] Workbox missing `html` in precache + no `navigateFallback` for offline SPA**
    `vite.config.ts:28` — `globPatterns` only includes `js,css,ico,png,svg,woff,woff2`. Without `html` and `navigateFallback: '/index.html'`, offline navigation to any route shows a browser error page instead of the cached SPA shell.

12. **[Testability] Command queue, useHydratedEvent, WebSocket store, and all 16 Pinia stores have zero unit tests**
    Only utility functions and one component have unit tests. The entire store/composable layer — including offline queue replay, hydration joins, cascade deletion, and optimistic rollback — is tested only via e2e. Prioritize: `commandQueue.spec.ts`, `useHydratedEvent.spec.ts`, `votes.spec.ts`, `websocket.spec.ts`.

13. **[Maintainability] `getInitials()` duplicated 3 times, `getMemberName()` duplicated 4 times**
    `HomePage.vue:213`, `MembersPage.vue:175`, `AuthenticatedLayout.vue:137` (getInitials); `HomePage.vue:66`, `SettlementSection.vue:55`, `EditAssignmentPopover.vue:22`, `ChoreCell.vue:22` (getMemberName). Extract both to `utils/member.ts`.

14. **[Correctness/Maintainability] `deleteSettlement` uses `mutate()` instead of `destroy()`**
    `stores/settlements.ts:16-19` — No optimistic removal; settlement stays visible until server responds. Inconsistent with other delete operations. Switch to `destroy()`.

15. **[Correctness/Maintainability] `updateAssignment` uses `mutate()` instead of `update()`**
    `stores/choreRosters.ts:149-166` — No optimistic UI for assignment edits (note, member, pin). Switch to `update()` with `choreAssignment` type for optimistic patching.

## Minor

16. **[Correctness] `useEventContextCommands` missing `event-chores` route**
    `composables/useEventContextCommands.ts:23` — The `eventDetailRoutes` set omits `'event-chores'`, so command palette context actions don't appear on the chores page. Add it.

17. **[Correctness] RSVP body building skips dates when explicitly `null`**
    `stores/rsvps.ts:18-20` — Truthiness check (`if (startDate)`) means `null` won't clear previously-set dates. Use `if (startDate !== undefined)` instead.

18. **[Correctness] `today` computed in `useEventsList` never re-evaluates past midnight**
    `composables/useEventsList.ts:19` — `computed(() => new Date().toISOString().slice(0, 10))` has no reactive deps. Events won't shift between current/upcoming/past until pool changes or page reload. Same pattern in `useEventsNeedingRsvp.ts:28`.

19. **[Correctness] `EventCreatePage` silently drops location fields**
    `pages/EventCreatePage.vue:17-25` — `handleSubmit` only passes `name`, `description`, `startDate`, `endDate` to `createEvent()`, dropping `locationName`/`latitude`/`longitude` from the form data.

20. **[Reliability] `isNetworkError` misses Safari's "Load failed" error message**
    `stores/commandQueue.ts:20-25` — String matching for "fetch" or "network" doesn't cover Safari's `"Load failed"`. On Safari with `navigator.onLine` true, network errors cause commands to be discarded instead of queued.

21. **[Reliability] WebSocket `online` event listener is never removed**
    `stores/websocket.ts:382-386` — Registered at module scope, never cleaned up on disconnect/logout. Reconnect logic fires even after logout (mitigated by auth check inside `connect()`). Move registration into `connect()` and removal into `disconnect()`.

22. **[Reliability] Pool persistence debounce can lose writes on page unload**
    `composables/usePoolPersistence.ts:47-49` — 500ms debounce before IndexedDB flush. Tab close within that window loses pending saves. Add a `beforeunload` or `visibilitychange` handler for final flush.

23. **[Reliability] `pendingCount` can drift from IndexedDB on errors**
    `stores/commandQueue.ts:60-81` — Maintained via manual increment/decrement, never re-synced after init. IndexedDB errors can cause drift. Re-sync from `dbCount()` after `processQueue` completes.

24. **[Observability] API client logs no request/failure information to console**
    `api/client.ts:98-146` — Shows user-facing toast on error but zero console output. JSON parse errors on line 127 are completely silent. Add `console.warn` for failed requests with method, path, status.

25. **[Observability] Service worker update failures silently swallowed**
    `registerSW.ts:33,42` — `.catch(() => {})` on `registration.update()`. Add `.catch((e) => console.warn('[SW] Update check failed', e))`.

26. **[Observability] Members store silently swallows all invite fetch errors**
    `stores/members.ts:53-57` — Catches all errors (intended for 403). Also silences 500s and network errors. Only silence 403 specifically; log others.

27. **[Observability] Auth `initialize()` catch treats all errors as network errors**
    `stores/auth.ts:89-95` — Programming errors (TypeError etc.) silently fall back to cached user. Distinguish network errors from bugs; log unexpected errors.

28. **[Performance] Non-computed template functions do per-event pool scans**
    `pages/HomePage.vue:115-139` — `attendeeCount()`, `unsettledExpenseCount()`, `unpaidTransferCount()` are regular functions called per event per render. Convert to computed Maps.

29. **[Performance] `cascadeRemove` triggers N version increments for N deletions**
    `stores/websocket.ts:280-301` — Deleting an event with 5 date ranges and 50 votes triggers 56+ version increments. Batch removals with a single version increment via a `removeMany` pool method.

30. **[Performance] `getAll` materializes full arrays with spread/reduce on every call**
    `stores/objectPool.ts:188-203` — Creates intermediate objects and arrays on every invocation. Hot path in hydration. Consider memoizing by type + version.

31. **[Performance] `isNewer` allocates Date objects on every comparison**
    `stores/objectPool.ts:12-14` — Two `new Date()` per call during `importObjects`. ISO 8601 strings are lexicographically sortable — compare directly with `>`.

32. **[Operability] Leaflet marker icons loaded from unpkg CDN**
    `components/common/StaticMap.vue:16-19` — Runtime dependency on third-party CDN. Breaks offline/PWA and fails if unpkg is down. Import marker images from the leaflet package directly.

33. **[Operability] No error handling for failed dynamic chunk imports after deploy**
    `router/index.ts:5-23` — No `router.onError` handler for stale chunk 404s. After deploy, users with cached HTML see blank page. Add handler that detects chunk load failure and reloads.

34. **[Operability] Race condition in gitSha-based cache-clear reload**
    `stores/websocket.ts:199-206` — `caches.keys().then(...)` is not awaited before `window.location.reload()`. Cache clearing may not complete before reload. Await the promise chain.

35. **[Operability] Leaflet CSS imported globally**
    `style.css:1` — All users download ~14KB of Leaflet CSS regardless of map usage. Move import into `StaticMap.vue`.

36. **[Security] Cached user in localStorage survives server-side session revocation**
    `stores/auth.ts:82-96` — If session is revoked server-side but server is temporarily unreachable, user appears authenticated with stale data. WebSocket will fail to auth. Consider a TTL on cached user.

37. **[Maintainability] Dead code: 4 deprecated WebSocket subscription methods**
    `stores/websocket.ts:416-436` — `subscribe`, `unsubscribe`, `subscribeToEvent`, `unsubscribeFromEvent` are no-ops with eslint-disable comments. Nothing calls them. Remove.

38. **[Maintainability] Dead code: ~10 unused interfaces in `types/index.ts`**
    `types/index.ts:3-126` — `User`, `Vote`, `VoteSummary`, `VotesResponse`, `VoteApiResponse`, `DateRange`, `Event`, `EventsResponse`, `EventResponse`, `CreateInviteRequest`, `AuthError` are never imported. Remove.

39. **[Maintainability] Duplicate type: `VoteResponse` defined in both `types/index.ts` and `types/pool.ts`**
    Keep in `pool.ts`, re-export from `index.ts` if needed.

40. **[Maintainability] `MeResponse` to `AuthUser` mapping repeated 3 times**
    `stores/auth.ts:61-70, 116-125, 258-267` — Extract a `mapMeResponseToAuthUser()` helper.

41. **[Maintainability] `formatAmount()` duplicated 3 times**
    `HomePage.vue:87`, `SettlementSection.vue:79`, `ExpenseSplit.vue:99` — Extract to `utils/format.ts`.

42. **[Maintainability] Barrel export `stores/index.ts` missing 4 stores**
    Missing: `useExpensesStore`, `useSettlementsStore`, `useChoreRostersStore`, `useRsvpsStore`.

43. **[Maintainability] `HomePage.vue` is 763 lines — oversized component**
    Extract dashboard sections into separate components (birthdays, settlements, current events, polls, RSVPs).

## Suggestions

44. **[Testability] Create shared test factories for pool objects**
    `ExpenseSplit.spec.ts` has local factories. Extract to `tests/factories.ts` with helpers for all pool types and a `createTestPool()` seeding function.

45. **[Testability] Remove scaffold `example.spec.ts`**
    `tests/unit/example.spec.ts` — Smoke test of HomePage provides negligible coverage.

46. **[Performance] `removePending` linear scan of all pending updates**
    `stores/objectPool.ts:252-268` — Maintain a reverse index `Map<pendingId, key>` for O(1) removal.

47. **[Observability] No frontend performance instrumentation**
    No timing of API calls, WebSocket reconnection, pool sync, or IndexedDB persistence. Consider `performance.mark`/`measure` on key paths.

48. **[Operability] Build warnings silently suppressed**
    `vite.config.ts:44-52` — `onwarn` suppresses `MIXED_EXPORTS` without logging. Document which modules trigger them.

49. **[Operability] No `Content-Security-Policy` header**
    `config/deploy/tayaway.nginx.conf` — Good security headers otherwise. Add CSP in report-only mode as defense-in-depth.

50. **[Reliability] Pool persistence callback not cleaned up on logout**
    `composables/usePoolPersistence.ts` — `stopPersisting()` is never called during logout. Call it alongside other cleanup in `auth.ts`.

51. **[Maintainability] Duplicated action trigger composable pattern**
    `useTaskActions.ts`, `useDateRangeActions.ts`, `useExpenseActions.ts` — Identical 11-line pattern. Could use a generic factory, but fine as-is given the small size.

52. **[Correctness] `dateRange` pool type has unused `voteIds` array**
    `types/pool.ts:84` — `PoolDateRange.voteIds` and `PoolDatePoll.dateRangeIds` are maintained but never used (hydration scans by FK instead). Either use them or remove them to avoid confusion.

53. **[Security] No CSRF token on state-changing requests**
    `api/client.ts:98-113` — Relies on `Content-Type: application/json` for implicit CSRF protection. Acceptable if backend enforces CORS + rejects non-JSON content types. Consider adding a custom header for defense-in-depth.
