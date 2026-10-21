# The small-web client — a development plan

*Status: **plan.** This specifies a Gopher and Gemini client for Agora — the browsing half of the desktop that
the project README leaves open ("further components (system preferences, more applications) are not yet
specified"). It is written in the house style of `WORKSPACE-PLAN.md` and `DEVELOPMENT-TOOLS.md`: every claim is
tied to a file that exists, every recommendation is marked as one, and the things that are refused are named
rather than left to be discovered. Nothing here is scheduled.*

**The name is not yet settled.** §7 recommends one and states the constraint. Until it is settled this document
says "the client", and the repository is referred to as `smolweb` because that names the subject and not the
product.

---

## Verdict

**Recommendation: build the Gopher client first, with no new dependencies, and decide on Gemini's TLS with
working code in hand.** The argument is in §1 and the ordering in §8. In one sentence: Gopher is a complete,
correct, end-to-end exercise of Agora's transport, text, icon and type-dispatch foundations at roughly one
week of cost, and it defers the only genuinely expensive decision — linking a TLS record layer — until the
transport seam it has to fit inside exists and can be looked at.

**Recommendation: the client is a new component repository, not a component of an existing one.** §6.

**Recommendation: it does not join `demo/agora-session.sh`.** That script starts exactly four things — the
window server, the wallpaper client, Workspace and the Dock — and adding a network client to that composition
is a statement about what Agora *is* rather than what it can run. The client gets its own `demo/` script.

**The case for building it at all** is not that a Gopher client is useful. It is that Agora has no browser and
should not get an HTML one. HTML, CSS and a JavaScript runtime are the subproject that consumes a desktop stack
— the reason `COCOA-10.11-SURFACE-PLAN.md` can describe a finishable surface for AppKit is that no part of
Agora's completeness claim depends on a rendering engine. Gemtext is nine line types and a Gopher menu is four
tab-separated fields. Both can be implemented *entirely* — not a subset, the whole format — for less effort than
`libagora-app/NSLayoutManager.m` (2,927 lines) already cost. The desktop gets a genuinely complete browsing
experience and pays nothing that threatens the completeness argument.

The second case is diagnostic. A small-web client is the cheapest full-stack test the platform has: it exercises
socket I/O, the run loop, non-`http` URL parsing, Launch Services scheme dispatch, the type model, the icon
lookup, and text layout — in one small program, with a format that is trivially faked on the other end of a
socket. If Agora's Foundation cannot carry a Gopher client, that is worth knowing before it carries something
larger.

---

## 1. What the premise actually gives the client

Measured against the tree, not assumed. Every row is a capability the client needs and a file that provides it.

| The client needs | What exists | Where |
|---|---|---|
| Parse `gopher://` and `gemini://` | `NSURL` — a generic scheme/host/port/path/query parts parser, not HTTP-specific | `libagora-base/NSURL.m` (1,973 lines; `-scheme`, `-host`, `-port`, `-path` at ~500–512) |
| A socket that can be written, read, and abandoned | A real libdispatch — `dispatch_io` over kqueue/epoll | `libagora-dispatch/src/io.c` (2,832 lines) |
| A cheaper socket floor | `CFSocket`, and the CFSocketStream bridge | `libagora-core/CFSocket.c`, `libagora-core/CFSocketStream.c` (246 lines) |
| Type char → type identifier | `UTType` with the standard tree | `libagora-launchservices/UTType.h` (`kUTTypeText`, `kUTTypeImage`, `kUTTypeAudio`, …) |
| Type → icon | Icon Services and the vendored Frost theme | `libagora-iconservices/IconServices.h` |
| `gopher://` and `gemini://` as claims on an application | `CFBundleURLTypes` parsing and the scheme default registry | `libagora-launchservices/LSInfo.h:84-85` (`LSCopyDefaultHandlerForURLScheme`, `LSSetDefaultHandlerForURLScheme`) |
| Opening a URL from anywhere in the desktop | `-openURL:` resolved through Launch Services | `libagora-app/NSWorkspace.h:60,68` |
| A list of menu items, one row per item | `NSOutlineView` and `NSTableView` | `libagora-app/NSOutlineView.m` (759), `NSTableView.m` (2,133) |
| A page of laid-out text | Text storage, layout manager, drawing, scroll view | `NSTextStorage.m` (311), `NSLayoutManager.m` (2,927), `NSStringDrawing.m` (273), `NSScrollView.m` (800) |
| Document → attributed string | `NSAttributedString` and paragraph styles | `libagora-app/NSAttributedString.h`, `NSParagraphStyle.h` |
| A window with a toolbar, a location field and a split | `NSWindow`, `NSToolbar`, `NSSearchField`, `NSSplitView` | `libagora-app/*.h` |

**One correction worth recording, because the name is misleading.** `libagora-app/tests/browser.m` is a test
for `NSBrowser` — the column view — and has nothing to do with a web browser. There is no browser anywhere in
Agora today. This client would be the first thing in the project that the word "browser" honestly describes.

---

## 2. What is missing, named

Five things. The first is the only one that changes a dependency.

### 2.1 TLS, and only for Gemini

Gopher is plaintext TCP on port 70. Gemini mandates TLS on port 1965, so **Gopher adds no dependency at all and
Gemini adds the entire TLS record layer.**

What the stack has today is `libcrypto`, not `libssl`: `libagora-base/CMakeLists.txt:47-49` links the system
OpenSSL on stated terms — *"Agora does not vendor or pin a TLS library. FNWebSocketHandshake.m needs SHA1 and
RAND_bytes from libcrypto"* — and `:126` links `OpenSSL::Crypto`. Hashing is present; the record layer, the
handshake, session resumption and the verification callback are not.

**Recommendation:** link `OpenSSL::SSL` rather than vendoring anything, because that is already the stated
convention for OpenSSL in this tree, and because Gemini's trust model needs a certificate-verification callback
with access to the peer certificate — which is exactly what the OpenSSL API exposes and what `libtls` also
exposes and what nothing smaller does.

**This is the largest single piece of work in the project, and it is not the user interface.** The plan is
ordered so that it is reached with everything around it already built and testable.

### 2.2 Gemini's trust model has nowhere to live yet

Gemini certificates are self-signed and trusted on first use: pin a fingerprint the first time a host is seen,
refuse on change, and — per the specification — **ignore validity dates entirely**, because a self-signed
certificate's dates are meaningless and every Gemini certificate in practice carries a very long or indefinite
lifetime. Client certificates exist, are optional, and are only sent when the server requests one.

So the client needs a persistent trust store of (host, port, fingerprint, first-seen, last-seen). Agora has no
established per-application writable location to put it in. `NSFileManager.h:279` declares
`NSApplicationSupportDirectory`, `libagora-core/include/CFPriv.h:207` has
`kCFApplicationSupportDirectory`, and `NSUserDefaults` is real (`libagora-base/NSUserDefaults.m`, 1,021 lines) —
but nothing in the tree establishes which of these an application should use, and no application has yet needed
to answer the question.

**Recommendation:** this is a decision the plan must force (§9), not something to inherit by accident. My
preference is a file under `NSApplicationSupportDirectory` named for the bundle identifier, with the format
documented and greppable — not `NSUserDefaults`, because a trust store is a security record and should be a file
a person can read, diff and delete.

### 2.3 `NSStream` is not the socket floor

`libagora-base/NSStream.m` is 382 lines, `NSInputStream.m` 339, `NSOutputStream.m` 329, and
`libagora-core/CFSocketStream.c` 246. They are not the abstraction to build a network client on, and
`NSStream.m:173` records a live refusal in the neighbourhood (`-[NSInputStream _cfStreamError] is not
implemented`).

**Recommendation:** the client opens and drives its own socket — `socket`/`getaddrinfo`/`connect`, non-blocking,
with a `dispatch_read`/`dispatch_write` or `dispatch_source` over the descriptor. `libagora-dispatch/src/io.c`
is the mature thing in this area and it is already a dependency of the stack.

**Refused, explicitly:** promoting a socket abstraction into `libagora-base` before the client proves what shape
it wants. One application is not evidence. If the shape survives both protocols it can be promoted then, with
two callers' worth of hindsight; §8 builds that promotion into the plan as an explicit later step rather than
letting it happen by drift.

### 2.4 `NSTextView` cannot click a link

`libagora-app/NSTextView.h` declares no `clickedOnLink:atIndex:`, no `linkTextAttributes`, and no
`NSTextViewDelegate` protocol at all. Gemini's document is made of links, so a rendering path has to answer
"which link is under this point".

**Recommendation, and this one matters for scope:** do not add link support to AppKit for this. The client owns
a page view holding its own line model — the parsed gemtext plus a hit map of rectangles to link targets — and
draws it. AppKit already provides what that needs (`NSStringDrawing`, paragraph styles, fonts, the scroll view)
without the client having to widen a component with 113 public headers and 101 implementations. If link
hit-testing turns out to be generally wanted, it is AppKit's to earn later with a second caller behind it.

**Consequence, stated honestly:** a hand-drawn page view means the client draws its own selection, its own
find-in-page, and its own text cursor if it ever wants one. That is the cost of not touching `NSTextView`, and
for a read-mostly document format it is a cost worth paying. An editable Gemini page is not a thing.

### 2.5 A blocked read cannot be interrupted

`libagora-base/FNCURLURLProtocol.h` documents the limitation in the existing transport: `-stopLoading` stops at
the next chunk rather than interrupting a blocked read. The client inherits the same problem in its own loop —
abandoning a connection to a host that has accepted the TCP connection and gone silent is the case that matters,
and it must be solved by *not blocking in the first place*: non-blocking connect, a timeout per state, and
closing the descriptor unconditionally when the user asks to stop.

This is not a difficult thing to get right. It is a difficult thing to get right *by accident*, so it is named
here.

---

## 3. The two protocols, as the client sees them

Short, because both are short, and the client's correctness is measured against these two descriptions rather
than against any implementation of them.

### 3.1 Gopher, per RFC 1436

- **Transaction.** Connect to port 70 (or the port in the URL). Send the selector, optionally TAB and the search
  query, then CRLF. Read until the server closes. There is no length, no status line, no negotiation, and no
  second request on the same connection. **EOF *is* the end-of-message marker**, which makes a byte cap
  mandatory rather than optional: a hostile or broken server never has to stop talking.
- **A menu** (item type `1`) is a sequence of lines, each split by TAB into: type character, display string,
  selector, host, port, and optionally a `+` field for Gopher+. A line that does not split into at least four
  fields is malformed and is dropped rather than guessed at.
- **Item types.** RFC 1436 defines `0` text, `1` menu, `2` CSO phone book, `3` error, `4` BinHex, `5` DOS,
  `6` uuencode, `7` index-search, `8` telnet, `9` binary, `+` redundant server, `T` tn3270, `g` GIF, `I` image
  and `h` HTML. Wide de-facto additions since are `s` sound, `i` informational text and `d` document, and
  lowercase `t` is seen in the wild where `T` is meant. All of them must be handled; an unrecognised type is
  treated as `9` (binary download), never as text — sniffing a hostile menu line as text is how a client ends up
  rendering garbage or worse.
- **A search item** (`7`) requires a query from the user, appended after a TAB. A selector containing a TAB is
  already a search selector; the client should not try to be clever about which is which.
- **Everything not implemented is answered honestly.** A `telnet`, `tn3270` or CSO item offers the address and
  says the client will not open it. Gopher+ is refused by name. There is no attempt to fetch a CSO phone book.

### 3.2 Gemini

- **Transaction.** Connect over TLS to port 1965 (or the URL's port), send the absolute URL terminated by CRLF,
  maximum 1024 bytes, with any fragment stripped. Read the response. Close.
- **Response.** Two status digits, a space, a meta string, CRLF — then, for `2x` only, the body, terminated by
  the server closing the TLS connection. Again the body has no length, so the byte cap is mandatory.
- **Status classes.** `1x` input (meta is the prompt; the client sends a *new* request with the input appended),
  `2x` success (meta is the MIME type), `3x` redirect (meta is the target URL), `4x` temporary failure and `5x`
  permanent failure (meta is a human-readable message to show, not parse), `6x` client certificate required. An
  unknown first digit is a permanent failure with the raw status shown.
- **Redirect bound.** The specification puts the five-redirect limit on the *server*; a client still needs its
  own counter, because the specification is not a promise about the server. Five, then a permanent failure the
  user can read.
- **TLS.** Version 1.2 minimum, SNI sent, and the verification callback is where TOFU lives: on an unknown host,
  record the fingerprint and proceed; on a known host, compare and refuse on mismatch with a message that says
  what changed and offers no "continue anyway" button. Validity dates are not checked (§2.2).
- **`text/gemini`,** the default MIME type when none is given, with a `charset` parameter defaulting to UTF-8 and
  an optional `lang`. Any other MIME type is not rendered — it is offered to the user as a save or a hand-off to
  whatever Launch Services says opens it.
- **Gemtext line types:** `# `, `## ` and `### ` (three levels, and no more), `* ` list item, `> ` quote,
  ```` ``` ```` as a toggle for preformatted blocks (text after the opening fence is alt text, not content),
  `=> ` link lines with an optional space-separated label, and everything else as plain text. There is no inline
  emphasis, no nesting, no tables and no images in the format. **This is the entire document model** and it is
  the reason this document can be precise about it.
- **Refused:** Titan (the upload protocol), `gemini://` uploads and fragments, `text/gemini;lang` localisation
  beyond passing the tag to the text system, and client certificates in v1 (§7).

---

## 4. Where the code lives

A new component repository, `smolweb`, following the project's one-component-one-repository rule, laid out like
`workspace` and `dock` — an application bundle at `Contents/<platform>/<arch>/<Name>`, per the layout
`demo/agora-session.sh` already assumes.

```
smolweb/
  SMTransport.h/.m          connect / write / read-to-EOF-cap / abort; optional TLS verify hook
  SMGopherSession.h/.m      one transaction: request bytes in, response bytes out
  SMGeminiSession.h/.m      one transaction, status line parsed, body streamed
  SMGopherMenu.h/.m         a menu → typed item array
  SMGemtextDocument.h/.m    gemtext → typed line array
  SMGopherWindow.h/.m       the list window
  SMPageView.h/.m           the page window's document view: lines, layout, hit map
  SMWindow.h/.m             what both windows share: location field, history, progress, error sheet
  SMHistory.h/.m            per-window back/forward
  SMTrustStore.h/.m         TOFU records (Gemini only)
  main.m                    the application
  tests/                    headless tests and a fake server, in the style of libagora-app/tests/
```

**Layering, and the direction it must not flow.** `SMTransport` knows about bytes and descriptors and nothing
about Gopher or Gemini. Sessions know about one protocol each and nothing about views. Documents know about
format and nothing about either. Windows know about views. Nothing in the client imports AppKit below the window
layer, so the parsers and the transport are testable without a window server at all — which is what makes the
headless test story in §8 possible.

**Two things deliberately not in `libagora-base`:** `SMTransport`, and the URL request formatting. Both are one
caller deep. §8 promotes them only if the Gemini work makes it two.

### 4.1 The `NSURLProtocol` seam, later rather than sooner

`NSURLConnection.m` (826 lines) describes itself as *"the engine over NSURLProtocol"*, consults
`+fnProtocolClassForRequest:` (`:241`, `:344`, `:399`) and implements `NSURLProtocolClient`. The seam is
therefore not theoretical: `FNCURLURLProtocol` is a working transport behind it, claiming `file`, `http` and
`https` (`FNCURLURLProtocol.m:367`), and the header states the ordering rationale — *"the plug-in point came
first because every transport is a plug-in."*

Writing `SMGopherURLProtocol : NSURLProtocol` would let `+[NSURLConnection sendAsynchronousRequest:]` load a
Gopher menu with no new code in the client. **Recommendation: do it, and do it after the client works, as a thin
facade over `SMGopherSession`.** The reason for the ordering is §2.2: Gemini's TOFU verification needs the peer
certificate inside the TLS handshake, and `NSURLProtocol` has no callback that exposes one. A transport written
the other way round — shaped to the seam first — would have to be restructured to reach the certificate. Written
as the client's own transport, it fits behind the seam with an adapter, and the seam then serves the desktop:
`gemini://` links in any Agora text view, opened by `-[NSWorkspace openURL:]` (`NSWorkspace.h:68`) through Launch
Services (`LSInfo.h:84`), landing in the client.

---

## 5. The two windows

Not one window with a mode switch. The two formats are for different things and the interfaces should say so.

### Gopher: the list

An `NSOutlineView` or `NSTableView` — one row per menu item, the display string as the label, and the item type
character mapped to a `UTType` and drawn with the Frost icon in the leading column. Type `1` rows disclose;
type `0` rows open a text window; type `7` rows prompt; type `9` and the image/sound types save.

This is the turbo-era Gopher client, and it is the best demonstration in the project of the type model and the
icon lookup working together — `LSInfo.h`'s UTI registry decides what a thing is, `IconServices.h` decides what
it looks like, and a single character off a socket drives both.

### Gemini: the page

A `NSScrollView` around `SMPageView`. Gemtext lines become an array of typed runs; the view lays them out with a
measure-into-lines pass and keeps the rectangles. Headings are larger and bold, quotes are indented and
rule-marked, preformatted blocks are in a fixed-width face and are never re-wrapped, and link lines render as a
distinct marker plus the label with the target available on hover and in the status area. Clicking a link line
opens it; clicking a non-link line does nothing.

The page view is where the text foundation gets its hardest real exercise so far: mixed fonts and sizes on one
page, indented blocks, unwrapped fixed-width runs, and a selection that spans all of it.

### Shared

One location field showing the absolute URL, editable. Back and forward honouring the per-window history. A
progress indicator for a transfer in flight, and a stop button that is honest (§2.5). An error surface that shows
the server's own message when there is one (`3` in Gopher, `4x`/`5x` in Gemini) rather than a code. A byte cap
that fails loudly with the limit stated.

---

## 6. Naming

`WORKSPACE-PLAN.md` states the rule this project follows: *"A third-party product's name is never used, in whole
or in part, for our software."* It then distinguishes two registers the project already uses — role names
(`Workspace`, `Dock`, `Widget Zoo`) and single evocative words (`Kestrel` for the window manager, `Argentum` for
the design language).

"Smolweb" is neither. It is an attitude rather than a protocol, it is spelled three ways in the wild, and no one
outside a conversation like this one recognises it. It is fine as the name of this document's subject and as the
repository name. It is a poor bundle identifier and a worse window title.

**Recommendation: `Ferry`** — in the second register, a small vessel that carries things between shores, which is
what the application does, and not a name anyone has shipped a browser under. The window class prefix would be
`SM`.

Alternatives, if that register is wrong: `Pocket` (a small case for small documents), `Landfall`, or naming the
two applications separately — `Gopher` and `Gemini` — which is historically the most accurate answer and has the
side effect of making the list-versus-page split look intentional. Against the separate-applications option: two
bundles, two registrations for two URL schemes, and two copies of the transport and the location field.

**The rule that does not bend:** whichever name is chosen, every class, file, target, executable and
user-visible string is named for it consistently, and no existing product's name appears anywhere in the
component.

---

## 7. Refusals, named

Each of these is a decision, not an omission.

- **No HTML rendering, ever, in this component.** A `Gopher` type `h` item and a Gemini `text/html` body are
  handed to whatever Launch Services says opens them, or saved. They are never displayed.
- **No Gopher+.** The `+` field is tolerated and ignored. Nothing negotiates.
- **No Titan, no `gemini://` uploads, no client certificates in v1.** Input is limited to the `1x`
  query-append case, which is what Gopher's search and Gemini's prompt both actually need.
- **No proxy, no aggregation, no capsule index, no search server.** The client is a client.
- **No global cache in v1.** History is per-window and holds URLs, not documents. A cache is a policy surface —
  freshness, eviction, what a stale page means in a medium with no `Cache-Control` — and none of it is needed to
  browse.
- **No `NSStream`-based transport.** §2.3.
- **No socket abstraction promoted into `libagora-base` before a second caller exists.** §2.3, §10.
- **No link support added to `NSTextView` for this client.** §2.4.
- **No entry in `demo/agora-session.sh`.** Verdict.
- **No tolerance of a malformed menu line or gemtext line by guessing.** A line that does not parse is dropped
  and, in a test build, reported. A document format this simple has no excuse for a heuristic.

---

## 8. The staged plan

Ordered so that each stage is provable on its own machine with no network, and so that the one expensive
dependency is reached last.

### S0 — The transport, proven against a fake server

`SMTransport`: non-blocking connect, write, read-until-EOF with a byte cap, per-state timeout, unconditional
abort that closes the descriptor. Proven against a socket the test opens itself, in the style of
`libagora-dispatch/tests/dispatch_io_net.c`.

*Proven by:* a headless test that (a) sends a fixed reply and reads all of it, (b) sends forever and confirms the
cap fires and the connection is closed, (c) accepts and then never replies, and confirms the timeout fires and
the abort closes it. The third case is the one §2.5 predicts will be got wrong by accident.

### G1 — The menu parser and the page parser, as pure functions

`SMGopherMenu` and `SMGemtextDocument`. Bytes in, typed arrays out, no I/O, no view.

*Proven by:* table-driven tests over the awkward cases — a menu line with three fields, a menu line with six, a
selector containing a TAB, an unknown item type, a gemtext document that opens a fence and never closes it, a
link line with no label, a heading with four hashes (which is not a heading).

### G2 — Gopher, end to end, in a window

`SMGopherSession`, the list window, the fixed-width text window, the location field, the history. This is the
first stage a person can use.

*Proven by:* a fake Gopher server in the tests directory serving a canned menu over `127.0.0.1`, and by hand
against a handful of real servers. **The fake server is part of the deliverable**, not a convenience: without it
the protocol tests depend on the network and rot.

### G3 — `gopher://` as a desktop-wide scheme

`CFBundleURLTypes` in the bundle's `Info.plist`, verified by
`LSCopyDefaultHandlerForURLScheme` (`LSInfo.h:84`) returning the client, and `-[NSWorkspace openURL:]`
(`NSWorkspace.h:68`) landing in it. Optionally the `SMGopherURLProtocol` facade (§4.1) so `NSURLConnection` can
load a selector.

*Proven by:* a test that asserts the registration, and by opening a `gopher://` URL from another application.

### G4 — The Frost icons, and Gopher item types as types

The item type character mapped through `UTType.h` and drawn from `IconServices.h`. Falls out of G2's row drawing
once the mapping exists.

*Proven by:* the existing icon and type tests' style — a small table asserting type character → `UTType` → the
representation actually asked for.

### G5 — TLS, and the trust store

`OpenSSL::SSL` linked on the `libagora-base` precedent (§2.1); verification callback implementing TOFU; the
decision from §2.2 resolved and `SMTrustStore` written; fingerprint change refusal with a message that names the
old and new fingerprints.

*Proven by:* a fake Gemini server with a self-signed certificate the test generates, over which (a) a first
connection records a fingerprint, (b) a second connection to the same fingerprint is accepted without a prompt,
(c) a connection presenting a different certificate is refused with the record unchanged.

**This stage is where the project either is or is not worth continuing**, and it is deliberately late enough that
the answer arrives cheaply.

### M1 — Gemini, end to end

`SMGeminiSession`, the status line, redirects with the bound, error messages as prose, `text/gemini` detection and
non-`text/gemini` hand-off, then the page view and its hit map.

*Proven by:* the fake TLS server from G5 extended to serve a status line and a body, plus the parser tables from
G1 becoming the renderer's inputs.

### M2 — `gemini://` as a scheme, and the page view's polish

The same integration as G3 for `gemini`. Selection, find-in-page if it is wanted, the link indicator and status
area.

### L1 — The two promotions, only if justified

`SMTransport` and the request formatting move into Foundation **if and only if** a second caller exists. The
honest reading of "a second caller" is not the `NSURLProtocol` facade — that is the same client wearing a
different hat. It is a different application. If there is none, they stay where they are, and this stage is
skipped and recorded as skipped.

---

## 9. Decisions this plan must force

1. **Is Gemini in the first release at all?** The recommendation is no — Gopher through G4, then decide, because
   after Gopher the transport's shape is known and TLS can be judged against it rather than imagined.
2. **Where does an application's persistent data live?** §2.2. `NSApplicationSupportDirectory` under a bundle
   identifier is my recommendation; `NSUserDefaults` is the alternative; nothing in the tree currently decides
   it, and this client is the first application that must.
3. **`OpenSSL::SSL`, `libtls`, or refusal of Gemini?** §2.1. All three are defensible; only the first is
   consistent with what `libagora-base/CMakeLists.txt:47-49` already says out loud.
4. **The name.** §6.
5. **Does the client ever write anything?** Gopher type `9` and non-`text/gemini` bodies imply a save. A save
   dialog is AppKit surface this project has not exercised from an application yet, and it is a real cost. The
   alternative — refuse to save in v1 and say so — is cheaper and less useful.
6. **Is a fixed-width face actually available?** Preformatted blocks need one, and the answer lives in
   `libagora-text`'s font handling rather than in this plan. If it is not, the client needs it and that is a
   dependency on a different component than the one this document is about.

---

## 10. What this plan deliberately does not do

- It does not propose a Foundation networking framework. One client is not evidence, and §8's L1 is the gate.
- It does not propose changes to `NSURLProtocol`, `NSURLConnection`, `NSURL` or `NSTextView`. The client is
  written against the surface those files already declare, and if that surface is insufficient the finding is
  recorded here rather than fixed by widening it in passing.
- It does not propose a bundled capsule, a home page, or any default content. An empty location field and a
  history that starts empty is the correct first-run experience for a client whose medium is someone else's
  server.
- It does not schedule anything. The stage count is not a schedule; G5 is the stage whose cost is unknown and the
  plan is arranged so that its unknown cost is the last thing that matters.
