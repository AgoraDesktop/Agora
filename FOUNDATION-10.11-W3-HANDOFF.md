# W3 — URLSession — handoff (W3a–W3c landed; W3d remains)

*State at the end of the session that completed three of the wave's four slices: **`NSURLSessionConfiguration` (47
doors)**, **the spine (`NSURLSession`'s data half, `NSURLSessionTask`, `NSURLSessionDataTask`, the five delegate
protocols)**, and **download + upload with their eleven factories**. The stream task and the thirteen task-scoped doors
(W3d) remain; this handoff is the place a continuation starts. Everything below was measured; §7 reproduces every
number.*

---

## 1. Where the tree is

37 suites green in the committed state. All API gates green.

| Gate | Reads |
|---|---|
| `foundation-api-10.11-census` | **204 of 219 classes**, **3,516 of 3,617 selectors** (101 missing), **36 of 40 protocols**, 182 of 182 functions |
| `foundation-api-census` (10.6) | `methods-declared` **4,147**, not-implemented 0 |
| `foundation-api-availability` | annotations **815/815**, 0 wrong · designated 125/143 present, 18 missing (the refused number cluster), extra 2 |
| `foundation-header-compile` / `-nullability` / `-strict-surface` | 202 headers alone × 3 modes · 0 nullability sites · 6 extension declarations hidden under the strict define |

The 15 missing classes and 101 missing selectors are the rest of the 10.11 surface: W3d (the stream task and the
task-scoped doors), W4 (notifications/extensions/item provider), W5 (XPC and script-task refusals). Two of the 101 are
the stream factories inside `NSURLSession`, which is otherwise complete.

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

## 2b. What landed: W3b, the spine (35 selectors, 5 protocols)

`NSURLSession.h` + `.m` + `tests/foundation_10_11_url_session.m` (62 cases), commit `676625d` in `libagora-base`.

**A task is an `NSURLProtocolClient`.** `+fnProtocolClassForRequest:` names the class that claims the request, one
instance is made with the task as its client, and `-startLoading` begins the transfer on the transport's own thread.
The client doors become the session delegate's messages, so the bytes, redirects and challenges are the ones
`FNCURLURLProtocol` already produces. What the slice adds:

| Shape | Rule |
|---|---|
| birth | a task is **suspended**; `-resume` starts it; `-suspend` stops the transfer and a later resume **restarts** it (the engine has no resumable transfer — the documented deviation) |
| lifetime | the session **retains itself per outstanding task**, which is also what keeps a task's unretained session pointer valid |
| delegate delivery | always on the session's queue; a nil queue becomes a serial queue the session owns, so completion handlers run even with no delegate |
| response | `-didReceiveResponse:completionHandler:` **blocks** the payload; data arriving meanwhile is held and delivered in order on Allow; Cancel ends the task; the two conversions are refused by name |
| redirects | the delegate decides; `currentRequest` moves only when followed; a refused redirect makes the 3xx the final response; the new protocol is in place before the old is autoreleased (the old frame is on the stack) |
| cancellation | `NSURLErrorCancelled`, state Canceling then Completed, `-error` set |
| authentication | task door before session door, mapped onto the challenge sender's actions; no delegate ⇒ default handling **without waiting**, so the transport never hangs |
| background | refused at session creation with the `FOUNDATION-REFUSE` line W5's census will read |
| task lists | `getTasks…` answers the outstanding tasks of each kind (upload/download arrays are empty until W3c); `-flush…` is a documented no-op; `reset…` empties the configuration's three stores |
| copies | `-copy` is a new **suspended** task on the same session — not a second handle on a running transfer |

Declared: `NSURLSession` with **18 of its 31 doors** (the data half), `NSURLSessionTask` (17), `NSURLSessionDataTask`
(0 own), and all five delegate protocols. The 13 download/upload/stream factories are **not declared**: their classes
are W3c/W3d, and a factory that cannot make its object is the stub §4.3 forbids.

Pin movements: classes 199 → 202, protocols 31 → 36, selectors 3,469 → 3,504; `selectors-offered` 3,568 → 3,616 and
`methods-declared` 4,100 → 4,135; availability 809 → 815 (`NSURLSession`/`NSURLSessionTask` at
`NSURLSESSION_AVAILABLE`, `NSURLSessionDataTask` at **10.10**, `getAllTasks…` 10.11, the `priority` pair 10.10).

## 2c. What landed: W3c, download and upload (12 selectors, 2 classes)

`NSURLSessionDownloadTask` (its one door is a refusal), `NSURLSessionUploadTask`, and the eleven factories — commit
`3bc18d0` in `libagora-base`.

| Shape | Rule |
|---|---|
| download | the body goes to a temporary file, the URL is handed to `URLSession:downloadTask:didFinishDownloadingToURL:` (or the completion block), the `didWriteData:…` progress door reports chunks, and the file is **removed when the call/block returns** (the removal lives inside the dispatched block) |
| download failure | an error or cancellation removes the half-written file and hands nothing over |
| upload | the body comes from data or a file (the file is read and put in the request); **streamed requests refuse by name** — the transport has no body-stream read door — and an unreadable file refuses with its path |
| resume data | refused in both directions: `downloadTaskWithResumeData:` answers nil by name; `-cancelByProducingResumeData:` calls its handler with nil and cancels |
| task lists | partition by kind: download first, then upload, then data (an upload descends from the data task) |
| completion forms | the download block is `(NSURL *, NSURLResponse *, NSError *)`; the base's delegate `didComplete` door is suppressed via `-fnHasOwnCompletion` |

**A REAL W3b BUG FOUND AND FIXED HERE.** A finish on the transport's thread racing a response disposition's flush
could enqueue the completion *before* the data it completed with (or lose the last chunks). The pending flag, the held
chunks and the enqueue are now one locked region (`@synchronized(self)`), and a finish that races a disposition waits
behind it. Proved by four consecutive clean runs of the 93-case test.

Pin movements: classes 202 → 204, `sel:NSURLSession` 18 → 29, selectors 3,504 → 3,516; offered 3,616 → 3,617 (the
download task's own door), **missing 112 → 101**; `methods-declared` 4,135 → 4,147; availability unmoved at 815.

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

1. **W3d — stream and the task-scoped doors.** `NSURLSessionStreamTask` (7, over a socket pair, plus
   `streamTaskWithHostName:port:` and the `NSNetService` form) and the thirteen task-scoped doors, declared in
   `NSURLSession.h` where Apple puts them: `NSURLCache` (3), `NSURLCredentialStorage` (4), `NSHTTPCookieStorage` (3)
   and `NSURLProtocol` (3 — `+canInitWithTask:`, `-initWithTask:cachedResponse:client:`, `-task`). Then the wave's
   acceptance test (redirect with a cookie, authentication challenge, task-scoped cookies, stream task).
2. **W4 / W5** after the family, per the plan.

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

# the two slices' own tests
cd build && ctest -R 'foundation_10_11_session_configuration|foundation_10_11_url_session' -V

# the census position
python3 ../libagora-app/tools/api-ledger census api/10.11/foundation-manifest.txt . --library build/libagora-base.so
python3 ../libagora-app/tools/api-ledger missing api/10.11/foundation-manifest.txt . --library build/libagora-base.so \
        --include ../libagora-core/include

# the availability position
python3 ../libagora-app/tools/api-ledger availability api/10.11/foundation-manifest.txt . \
        --pin tests/api-10.11-annotations.txt

# the whole suite (37 in the committed state)
cd build && ctest
```
