# M2 — behaviour — COMPLETE (Foundation's part of the 10.11 plan is finished)

*M1 declared the surface (W0–W7); M2 makes it behave. This file records the six behavioural suites, the two W3 debts
that were real defects, the refusal instrument's own correction, and what the next plan inherits.*

## 1. Where the tree is

**46 libagora-base suites green; every gate green.**

| Gate | Reads |
|---|---|
| `foundation-api-10.11-census` | 219 of 219 classes, **3,744 of 3,744 selectors**, 40 of 40 protocols, 182 of 182 functions |
| `foundation-api-census` (10.6) | `methods-declared` **4,376**, not-implemented 0 |
| `foundation-api-availability` | **917/917**, 0 wrong · designated 140 of 158 present |
| `foundation-header-compile` | 226 headers alone in ObjC, ObjC++ and ARC, plus the umbrella — **681/681** |
| `foundation-header-nullability` | same set, 0 missing |
| `foundation-refusal-census` | **52** doors over eight files, both directions |
| Swift import probe | `agora-import-probe`: 22/22 family checks |

## 2. The behavioural tier, suite by suite

| Suite | Cases | What it pins |
|---|---:|---|
| `foundation_10_11_url_session` | **133** | a loopback HTTP server drives data/upload/download tasks, redirects (followed and refused), cancellation, the task-scoped cache/cookie/credential doors, the **session's own cookie store**, and **an authentication challenge end to end** |
| `foundation_10_11_progress` | 19 | the tree, KVO on the derived keys, indeterminate, cancellation down, the per-thread current stack, publish/unpublish in process |
| `foundation_10_11_url_components` | 32 | RFC 3986 parse/encode, query items, malformed escapes, relative resolution |
| `foundation_10_11_formatting` | 19 (+19 byte-count, +39 person-name) | the three unit styles, the plural rules, byte-count bases, person-name ordering under five languages |
| `foundation_10_11_user_notification` | 16 | centre state, delegate consultation, removal doors, delivery refusing by name |
| `foundation_10_11_refusals` | **53** | **every one of the 52 `FOUNDATION-REFUSE` doors**, by its named line and its documented return |

The wave's own callers from W6/W7 remain: `foundation_10_11_ordered_set` (14), `foundation_10_11_metadata_version` (13),
`foundation_10_11_operation_progress` (20), `foundation_10_11_tail` (27), `foundation_10_11_scripting_archive` (15).

## 3. The two W3 debts — and one was a defect, not a missing test

**(1) Cookies.** `NSURLSessionConfiguration -HTTPCookieStorage` was configuration nothing consulted: the transport
kept cookies in the process-wide store. FNCURLURLProtocol now asks its client (the task) for the store through a
PRIVATE first-party selector — the same seam it already used for body-stream re-sends — and a client without it gets
the old behaviour exactly. The suite asserts all three facts against a private store: a `Set-Cookie` lands there, the
shared store stays empty, and a seeded cookie is SENT by the next transfer.

**(2) Authentication — this one could not have passed a test before.** The dispatch was implemented (task door before
session door; the four dispositions mapped onto the sender's actions), but the transport asked the client and then read
its own two locals the instant the ask returned, while a session answers the challenge on its **delegate queue**,
asynchronously. So `disposition` was always `-1`, and a 401 through a session never retried. The fix is the wait the
transport's comment already claimed: the sender's continuation signals a condition, the transfer thread waits for it,
and the wait is BOUNDED (thirty seconds; a timeout is read as "no answer", the same outcome as a client that declines —
Apple would hang). The suite drives 401 → task-delegate credential → ONE re-issue carrying
`Authorization: Basic YWdvcmE6c2VjcmV0` → 200, and asserts the session's door was never needed.

## 4. The refusal instrument corrected itself

`foundation_10_11_refusals` calls every refusal door once, captures stderr, and checks the line NAMES the door and the
return is the documented one. Because it asserts a COUNT as well as the calls, it found that the claims census had been
counting two COMMENTS as doors: `NSURLSession.m`'s `#include` comment ("the FOUNDATION-REFUSE line") and
`NSXPCConnection.m`'s header sentence. Both comments now say what they mean without spelling the token, the census is
**52**, and the suite fails if its own count drifts. (The count history in `tests/refusal_census.txt` keeps 54 → 52
and why.)

Two doors needed the runtime rather than the compiler: `NSProxy`'s `-allowsWeakReference`/`-retainWeakReference` are
`NS_UNAVAILABLE`, so the suite calls them through the selector's IMP — which is exactly the caller the refusing body
exists for.

## 5. What the plan now says

`FOUNDATION-10.11-PLAN.md` §5's W3 debt paragraph and §7 are records of completion; the milestone list's M2 line says
DONE. The Foundation half of the 10.11 plan is finished: M1 (surface) from W0–W7 and M2 (behaviour) here.

## 6. What the next plan inherits

- **`COCOA-10.11-SURFACE-PLAN.md` §12.2** is the multi-framework M2 (AppKit's controls/text/documents/panels,
  Workspace, appearance, accessibility, PDF). Foundation's part is done; the AppKit tier's M2 is the large one and has
  its own callers (`libagora-app`'s 193 tests, two of which are pre-existing failures from uncommitted AppKit work in
  the parent checkout — `appkit-menu-headless` and `appkit-api-census`'s `methods-declared` drift — neither caused by
  Foundation).
- **`SWIFT-FOUNDATION-PARITY-PLAN.md`** owns the Swift overlay; `swift-interop-probe` is the import gate it can build on.
- The refusal discipline is the pattern to carry: a named line, a census entry, and a caller that asserts both. The
  census now counts DOORS, so a new refusal comment that spells the token will fail the gate — which is the intended
  direction.
