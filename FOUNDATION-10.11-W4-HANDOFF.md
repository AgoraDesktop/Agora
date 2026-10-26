# W4 — notifications, extensions, item provider — handoff (COMPLETE)

*State at the end of the session that completed W4 — all 7 classes, 3 protocols, 77 selectors.*

## 1. Where the tree is

39 suites green; all API gates green.

| Gate | Reads |
|---|---|
| `foundation-api-10.11-census` | **212 of 219 classes**, **3,615 of 3,701 selectors** (86 missing), **38 of 40 protocols**, 182 of 182 functions |
| `foundation-api-census` (10.6) | `methods-declared` **4,246**, not-implemented 0 |
| `foundation-api-availability` | annotations **853/853**, 0 wrong · designated 127/145 present, 18 missing (the number-cluster refusal), extra 2 |

## 2. What landed: W4a (4 classes, 1 protocol, 24 selectors)

Commit `36e6f09` in `libagora-base`.

- **`NSExtensionItem`** — copyable, securely codable, four copied values (attributed title/content, attachments, userInfo);
  the archive round-trips through the secure allow-list (`NSCoding.h` is imported for the protocol itself).
- **`NSExtensionContext`** — `inputItems` answers an empty array; `completeRequestReturningItems:completionHandler:`,
  `cancelRequestWithError:` and `openURL:completionHandler:` REFUSE BY NAME (no extension process) and the two handlers
  are still called with NO.
- **`NSItemProvider`** — type identifier → load handler map plus a preview handler; file form registers `public.data`
  and returns the file's bytes; an unregistered type answers an error. TWO DEVIATIONS, stated in the header: "conforms"
  means "is registered" (no UTI hierarchy), and the handler runs on the calling thread.
- **`NSFileAccessIntent`** — URL-and-kind value (10.10), declared in `NSFileCoordinator.h` where 10.11 puts it.
- **`NSExtensionRequestHandling`** — the protocol an extension implements; nothing here sends it.

The test (`foundation_10_11_extension.m`, 17 cases) pins the secure archive, the refusals with answered handlers, item
and file loading by type, and the intent.

## 3. What landed: W4b (3 classes, 1 protocol, 53 selectors)

Commit `536d045` in `libagora-base` (the notification family).

- **`NSUserNotification`** — a copied value: every object door copies on the way in, `contentImage` is retained and
  typed `id` (Apple's type is AppKit's NSImage; Foundation imports no AppKit), the activation constants carry Apple's
  numbers 0–4, the 10.9/10.10 doors carry their eras, and `-copy` carries every value.
- **`NSUserNotificationAction`** — the identifier/title pair from the one factory, copyable.
- **`NSUserNotificationCenter`** — an in-process ledger: the singleton, scheduling state, replacement of the scheduled
  list, and a `-deliverNotification:` that CONSULTS the delegate's `-shouldPresentNotification:`, REPORTS its answer in
  the refusal line, and then refuses by name. Nothing is recorded as delivered, because nothing was.
- **`NSUserNotificationCenterDelegate`** — the three optional doors.

The test (`foundation_10_11_user_notification.m`, 16 cases) pins the value/copy, the action, the scheduling state, the
delegate consultation and the refusal.

## 4. What remains

**W5** — XPC's four classes and two protocols and the three script-task classes, all refusals, plus the **refusal
census** (`tests/claims_census.cmake` + `tests/refusal_census.txt`). The `FOUNDATION-REFUSE` lines W3/W4 added
(background session, streamed upload, resume data, stream TLS, group container, unresolved NetService, extension
requests, notification delivery) are its first entries. Then **W6** (the selector tail: 86 missing selectors and the
`NSCoding` conformances) and **W7** (the umbrella, the 26 header names, the client gates).
