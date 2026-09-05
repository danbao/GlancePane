# Reliability improvements

Each item is delivered as a separate pull request, merged in order after tests,
the public-tree audit, packaging, and secret scanning pass.

| Order | Change | Acceptance scenarios | Status |
| --- | --- | --- | --- |
| 1 | Weather request lifecycle | Hide and re-enable during a request; late completions cannot replace or clear a newer request. | Implemented |
| 2 | Weather cache identity and freshness | Reject another location/provider at every read; preserve timestamps on complete failure; retain partial fallback. | Implemented |
| 3 | Differential configuration updates | Appearance edits preserve feeds and protection timers; only changed feeds restart; only display changes reposition the window. | Implemented |
| 4 | Window recovery scheduling | A failed first display retry preserves later retries; lock/sleep suspends recovery; hidden windows ignore pointer input. | Implemented |
| 5 | Background system sampling | Slow collection does not block the main actor; collectors remain serial; stopped or superseded samples cannot publish. | Planned |
| 6 | Dashboard rendering regressions | Test the production composition, backgrounds, scaling, offsets and rest overlay; group tests by domain. | Planned |

Keep the configuration schema, cache privacy, native UI behavior, and offline
test fixtures compatible. Use the existing hand-written test runner. New tests
exercise observable behavior through the dashboard, weather, window lifecycle,
system collection and rendering interfaces.

Run a targeted test while developing with
`GLANCEPANE_TEST_FILTER="weather" sh scripts/test.sh`. Omitting the filter runs
the entire suite. No matching tests is an error.
