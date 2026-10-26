# W4 — notifications, extensions, item provider — handoff (W4a landed)

*State at the end of the session that took the extension half of W4. The notification half remains.*

## 1. Where the tree is

38 suites green; all API gates green.

| Gate | Reads |
|---|---|
| `foundation-api-10.11-census` | **209 of 219 classes**, **3,562 of 3,648 selectors** (86 missing), **37 of 40 protocols**, 182 of 182 functions |
| `foundation-api-census` (10.6) | `methods-declared` **4,193**, not-implemented 0 |
| `foundation-api-availability` | annotations **838/838**, 0 wrong · designated 126/144 present, 18 missing (the number-cluster refusal), extra 2 |

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

## 3. What remains: the notification family (3 classes, 1 protocol, 53 selectors)

`NSUserNotification` (39), `NSUserNotificationCenter` (11), `NSUserNotificationAction` (3), and
`NSUserNotificationCenterDelegate` (3 optional doors). The plan's shape: an in-process centre that keeps scheduled and
delivered state, refuses delivery BY NAME (no notification daemon exists), and consults its delegate before presenting.
`NSUserNotification` is a mutable value with `NSCopying`; its 10.9/10.10 doors (`identifier`, `contentImage`,
`responsePlaceholder`, `response`, the two `additionalAction…` doors) carry their eras.

After that: **W5** (XPC + script-task refusals and the refusal census; the `FOUNDATION-REFUSE` lines from W3/W4 are its
first entries), **W6** (the selector tail) and **W7** (the umbrella, header splits, client gates).
