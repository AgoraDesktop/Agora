# W3 — URLSession — handoff (W3a landed)

*State at the end of the session that began W3 and completed its first slice: **`NSURLSessionConfiguration`, all 47
doors**, in the tree, tested, and pinned. The wave is XL and the other six classes are still to write; this handoff is
the place a continuation starts. Everything below was measured; §7 reproduces every number.*

---

## 1. Where the tree is

34 suites green in the committed state (the tree's 33, plus W3a's own test). All API gates green.

| Gate | Reads |
|---|---|
| `foundation-api-10.11-census` | **199 of 219 classes**, **3,469 of 3,568 selectors** (99 missing), 31 of 40 protocols, 182 of 182 functions |
| `foundation-api-census` (10.6) | `methods-declared` **4,093**, not-implemented 0 |
| `foundation-api-availability` | annotations **809/809**, 0 wrong · designated 125/143 present, 18 missing (the refused number cluster), extra 2 |
| `foundation-header-compile` / `-nullability` / `-strict-surface` | 202 headers alone × 3 modes · 0 nullability sites · 6 extension declarations hidden under the strict define |

The 20 missing classes and 99 missing selectors are the rest of the 10.11 surface: W3b–W3d (URLSession),
W4 (notifications/extensions/item provider), W5 (XPC and script-task refusals).

---

## 2. What landed: W3a, `NSURLSessionConfiguration` (47 → 0)

`NSURLSessionConfiguration.h` + `.m` + `tests/foundation_10_11_session_configuration.m` (48 cases), commit `a05b116`
in `libagora-base`.

**The class has no transport, so its contract IS the defaults, the three factories and the copy.** The test measures
all three:

| Fact | Value pinned |
|---|---|
| cache policy | `NSURLRequestUseProtocolCachePolicy` |
| request / resource timeout | 60 s / 7 days |
| service type, cellular, discretionary, launch events | default, ON, OFF, ON |
| proxy dictionary, additional headers | **empty dictionary, not nil** |
| TLS minimum / maximum | `kSSLProtocolUnknown` (0) both |
| pipelining, set-cookies, cookie policy | OFF, ON, `NSHTTPCookieAcceptPolicyAlways` |
| connections per host | 6 |
| stores | the three shared ones; nil accepted and meaning "none" |
| identifier / container / protocol list | nil, nil, nil |
| ephemeral | private cookie + credential stores, private cache with **diskCapacity 0** and 4 MiB memory |
| background | identifier set, otherwise default's shape; deprecated factory is the same configuration |
| copy | dictionaries/protocol array copied, stores retained, original and copy independent in both directions |

**Two design facts worth carrying forward:**

1. **`SSLProtocol` is declared in the header**, because this tree has no Security framework and Apple's property type
   lives in `<Security/SecureTransport.h>`. The tag and values are SecureTransport's, read from the 10.11 SDK header
   (0, 2, 4, 7, 8, 9 plus legacy 1, 3, 5, 6), and the test pins the numbers. TLS is libcurl's, configured by its own
   rules, so the two properties are **recorded policy**, and the header says so.
2. **`NSURLSessionConfiguration` is deliberately not in `Foundation.h`.** The umbrella takes the session family in W7,
   once all seven classes exist (§63.159's removal comment gets replaced there). Until then a test or client names
   `#import <Foundation/NSURLSessionConfiguration.h>` directly.

**Pin movements** (all deliberate, each with a comment in the pin): 10.11 census classes 198 → 199, selectors
3,422 → 3,469; both censuses' `methods-declared` 4,046 → 4,093; availability candidates and present 800 → 809 (the
class era `NSURLSESSION_AVAILABLE` plus the eight selector eras the reference carries: the deprecated background
factory, the identifier factory, the discretionary pair, the shared-container pair and the extended-idle pair).
`designated-*` and `annotations-extra` unmoved.

---

## 3. The design the remaining slices follow (§4.1 of the plan)

URLSession is a **task state machine over the transfer engine that is already here**, not a second HTTP stack:

- `NSURLConnection` drives an `NSURLProtocol` instance with itself as the client (`+fnProtocolClassForRequest:`,
  one instance, `-startLoading`). W3b's task does the same: it IS an `NSURLProtocolClient`, and the protocol's seven
  client doors become the task's delegate messages.
- `FNCURLURLProtocol` is the libcurl bridge; it already reports data incrementally, redirects as a notification
  (the client decides whether to follow), authentication challenges through the sender, and the response.
- Delegate delivery goes to the session's `NSOperationQueue`; a nil queue means a serial queue the session owns
  (Apple's rule). `NSURLConnection` already proves the `-addOperationWithBlock:` shape.
- Task state, `priority`, `taskIdentifier`, `originalRequest`/`currentRequest`, `countOfBytes…`, `response`, `error`,
  `taskDescription` live on `NSURLSessionTask`; `NSProgressReporting` is already adoptable (W2's `NSProgress`).
- Authentication ordering: the **task's** delegate is consulted before the session's; see the dispatch rules in the
  plan and in `NSURLConnection.h`'s precedence note.
- **Refused by decision, not by omission:** background sessions (`+sessionWithConfiguration:` answers nil with a
  `FOUNDATION-REFUSE` line when the configuration carries an identifier), `-cancelByProducingResumeData:` (resume data
  is a platform artefact this tree does not have), and `-flushWithCompletionHandler:` beyond a documented no-op.

---

## 4. What remains, in the order I would take it

1. **W3b — the spine.** `NSURLSession` (31 doors), `NSURLSessionTask` (17), `NSURLSessionDataTask` (0 own),
   `NSURLSessionDelegate`, `NSURLSessionTaskDelegate`, `NSURLSessionDataDelegate`, the completion-handler forms, and the
   session's configuration copy. Test: a loopback HTTP server (the existing `foundation_behaviour_3` runs one) driving a
   GET and a POST with delegate callbacks and a completion handler.
2. **W3c — download and upload.** `NSURLSessionDownloadTask` (1 door: the resume-data refusal), `NSURLSessionUploadTask`
   (0 own), download to a destination URL, upload from `NSData` and from a file.
3. **W3d — stream and the task-scoped doors.** `NSURLSessionStreamTask` (7, over a socket pair), `NSURLSessionStreamDelegate`,
   and the task-scoped additions to `NSURLCache` (3), `NSURLCredentialStorage` (4), `NSHTTPCookieStorage` (3) and
   `NSURLProtocol` (3 — `+canInitWithTask:`, `-initWithTask:cachedResponse:client:`, `-task`). Then the wave's
   acceptance test (redirect with a cookie, authentication challenge, task-scoped cookies, cancellation, stream task).
4. **W4 / W5** after the family, per the plan.

Every slice must keep `methods-declared-not-implemented` at 0: a declared selector needs a body, and a refusal is a
body that names itself (`FOUNDATION-REFUSE`), which is W5's census instrument.

---

## 5. Working-tree caveat — read this before editing

**A concurrent editor is active in this same `libagora-base` worktree**, converting `NSRunLoop`/`NSTimer` to a
`CFRunLoop` façade. During this session it briefly left the tree uncompilable (an `#import` inside an
`NS_ASSUME_NONNULL` region) and it inserted its `runloop_cf` test into the same `tests/CMakeLists.txt` hunk W3a was
editing. What was done about it:

- W3a's commit stages **only** its own files. The `tests/CMakeLists.txt` registration was staged from a hand-built
  index (HEAD's file + W3a's block), and the working copy was restored afterwards, so the commit contains no line of
  the concurrent edit. `git show --stat a05b116` proves it.
- The working tree still carries the editor's `NSRunLoop.*`, `NSTimer.h`, `tests/runloop_cf.m` and its
  `tests/CMakeLists.txt` lines. **Do not `git add -A`** while they are there; stage named paths.
- The 35-test run that included their `runloop_cf` was green, but that test is not part of W3a's commit.

---

## 6. What did NOT change (and should not)

- `Foundation.h` still states that the session family is not in the umbrella, and it is **true** for now. W7 replaces
  that comment and re-admits the family; doing it in W3a would have put a half-family in the umbrella.
- The 10.6 census is unmoved in classes and selectors (URLSession is 10.9, outside that denominator); only
  `methods-declared` moved, because that number counts this tree's declarations, not Apple's.
- No designated-initializer marker: the configuration has no initializer in the graph (Apple's class is made by its
  factories), so it contributes nothing to that pin.

---

## 7. Reproducing every number

```sh
cd libagora-base

# the class's own test
cd build && ctest -R foundation_10_11_session_configuration -V

# the census position
python3 ../libagora-app/tools/api-ledger census api/10.11/foundation-manifest.txt . --library build/libagora-base.so
python3 ../libagora-app/tools/api-ledger missing api/10.11/foundation-manifest.txt . --library build/libagora-base.so \
        --include ../libagora-core/include

# the availability position
python3 ../libagora-app/tools/api-ledger availability api/10.11/foundation-manifest.txt . \
        --pin tests/api-10.11-annotations.txt

# the whole suite (34 in the committed state; a concurrent run-loop test may make it 35)
cd build && ctest
```
