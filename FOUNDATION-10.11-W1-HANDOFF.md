# W1 — the availability layer — handoff

*State at the end of the session that closed W1's two remaining residues: the nullability sweep and
`AGORA_EXTENSION` for the post-10.11 surface. W1 is now complete. Everything below was measured; §6 reproduces every
number.*

---

## 1. Where the tree is

All **33** suites green (the 31 behaviour suites plus the two gates this session added), and nothing is half-applied.

| Gate | Reads |
|---|---|
| `foundation-api-census` (10.6) | 173 of 173 classes, 2,840 of 2,840 selectors, 23 of 23 protocols, 180 of 180 functions · `methods-declared` 4,046 · not-implemented 0 |
| `foundation-api-10.11-census` | 198 of 219 classes, 3,422 of 3,521 selectors (99 missing), 31 of 40 protocols, 182 of 182 functions |
| `foundation-api-availability` | annotations 800/800, 0 wrong · designated 125 of 143 present, 18 missing (the number-cluster refusal), extra 2 |
| `foundation-header-compile` | 201 headers alone in ObjC/ObjC++/ARC, plus the umbrella (606 compilations) |
| **`foundation-header-nullability`** (new) | **0** distinct declaration sites missing a specifier, deduped across every probe and mode |
| **`foundation-strict-surface`** (new) | the umbrella compiles under `-DAG_TARGET_OS_X_10_11`, and **6** extension declarations are unavailable there and available in the normal build |

The 99 missing 10.11 selectors and 21 missing classes are the **surface** debt (W2 onward), not W1: W1 was the
availability layer — versions, designated initializers, nullability, extensions — and it is closed.

---

## 2. What landed, and the surprise in each part

One commit in `libagora-base` (`da601ad`).

### 2a. The nullability sweep: 411 warning lines → 9 declaration sites → 0

The recorded residue was "**411 `-Wnullability-completeness` warnings across 194 headers**". That number is a
**warning-line count**, and it is misleading twice over: clang repeats an included header's warning in every probe
that reaches it, and the three client modes repeat each other. The distinct declaration sites were **nine, in six
headers**:

| File | Sites | What the pointer is |
|---|---:|---|
| `NSObjCRuntime.h` | 2 | `Protocol`'s `-name`/`-description` properties (the category's `-isEqual:` is nullable) |
| `FNZone.h` | 2 | the recorded object pointer, beside a **nullable** zone argument |
| `NSError.h` | 2 | the recovery protocol's error — the subject, never absent |
| `NSAttributedString.h` | 1 | the RTFD writer seam: nullable return and dictionary, nonnull string |
| `NSMetadata.h` | 1 | the four notification names (the compiler names the first of the run) |
| `NSPersonNameComponentsFormatter.h` | 1 | the eight attribute keys, the same way |

**The rule that makes a header audited** (measured, not guessed): clang checks a header only when a probe *includes*
it — a header compiled as the main file never warns — and then it reports unannotated pointers in a file that already
carries annotations elsewhere. It names the **first** site of a run of same-shaped globals and then stays quiet, which
is why the four `extern NSString *const` names in `NSMetadata.h` produced one warning: **annotate the whole run, not
the one the compiler named**, or the gate goes green over three unannotated neighbours.

The recipe is the surface plan's F6 rule: annotate what the implementation **accepts**. The RTFD writer's return is
`_Nullable` because the AppKit writer refuses a range past the string; its dictionary is `_Nullable` because
`documentAttributes:` is; the notification names are `_Nonnull` because Apple's globals are.

### 2b. `AGORA_EXTENSION`: the post-10.11 surface, marked and hideable

`AGORA_EXTENSION` is defined in `NSObjCRuntime.h` beside `NS_UNAVAILABLE`:

```c
#if defined(AG_TARGET_OS_X_10_11)
# define AGORA_EXTENSION __attribute__((unavailable("this declaration postdates the 10.11 surface")))
#else
# define AGORA_EXTENSION
#endif
```

It is deliberately **not** like the availability spellings beside it, which are inert here (D12): clang on this host
cannot warn about a macOS version, but it **can** act on `unavailable`. So a strict client is told *which* declaration
is later than the target by name, rather than by a missing-name error.

| Declaration | Version | Note |
|---|---|---|
| `NSDateInterval` | 10.12 | |
| `NSISO8601DateFormatter` | 10.12 | |
| `NSSecureUnarchiveFromDataTransformer` | 10.14 | declared in `NSValueTransformer.h` in those SDKs, which is why a header of its own name is not found |
| `NSRelativeDateTimeFormatter` | 10.15 | |
| `NSDateIntervalFormatter -stringFromDateInterval:` | 10.12 | the one post-10.11 **selector** that names an extension type; without its marker the strict umbrella did not compile |
| `NSFileProviderService` | **none, on purpose** | the 10.11 reference does not declare it and this tree has no sourced minor version, so none is invented |

**The versions were sourced, not remembered.** They come from the 10.12/10.14/10.15 SDK header facts at the same
source `api/10.11/README.md` names for regenerating the manifest (`API_AVAILABLE(macosx(10.12))` and friends). This is
the plan's §4.12 rule: a hand-written version is exactly the drift the ledger exists to catch.

The surprise worth keeping: **hiding a class is not enough if a 10.11 class's header mentions it.** Marking
`NSDateInterval` unavailable broke the strict umbrella at `NSDateIntervalFormatter.h`'s interval door — which is
itself post-10.11, so it needed the marker too. That is what the umbrella compile in the gate is for.

---

## 3. The two gates, and why each can fail

- **`foundation-header-nullability`** (`tests/header_nullability.cmake`, pin `tests/api-10.11-nullability.txt`).
  201 headers × 3 modes with `-Wnullability` and `-Wnullability-completeness`; warnings are deduped by
  `header:line:column` across every probe and mode, and the count is compared with the pin (`nullability-sites 0`).
  **Proved to fail:** an injected unannotated pointer measured **2 sites, not 6** — the dedupe is real.
- **`foundation-strict-surface`** (`tests/strict_surface.cmake`). Three checks: the umbrella compiles under
  `-DAG_TARGET_OS_X_10_11`; each of the six marked declarations is unavailable there *with an `unavailable`
  diagnostic*; and the same use compiles without the define (a marker that **hid** a door would be the removal
  §4.1 forbids).

The suite went from ~42 s to ~79 s; the nullability gate is the 35 s of that (it is the same 600-compilation shape as
header-compile), and both stay comfortably under the plan's "few minutes" bound.

---

## 4. What moved, and what did not

Nothing moved in the ledger, and that is the correct answer:

- `annotations-extra` stays 0 — the marked classes postdate the 10.11 manifest, so they are not "extra facts about a
  door Apple declares".
- `designated-*` and `methods-declared` unchanged (4,046) — no declaration was added or removed, only marked.
- The censuses are unchanged; the nullability sweep touches pointers, not names.

The one deliberate asymmetry: `NSFileProviderService` is marked without a version token. If a later SDK checkout
sources its minor release, add it then — do not guess it.

---

## 5. What remains

W1 is closed. The plan's W2 and later are the **surface** waves: the 21 missing 10.11 classes and 99 missing selectors
(`api-ledger missing` names them), then behaviour. Nothing in the availability layer is waiting.

One known piece of tree noise, not this session's: `Testing/Temporary/LastTest.log` and `CTestCostData.txt` are
**tracked**, so every test run dirties the tree. They are not build products by the `.gitignore`'s definition, and
this session reverted the log rather than committing it. Un-tracking them (`git rm --cached` + a `.gitignore` line) is
a tidy-up worth doing in a quiet moment.

---

## 6. Reproducing every number

```sh
cd libagora-base

# the two new gates
ctest -R 'foundation-header-nullability|foundation-strict-surface' -V

# the nullability count without the gate (distinct sites, all three modes)
#   the gate's own message prints it: "N declaration site(s) missing a specifier (pin 0)"

# the availability/designated position
python3 ../libagora-app/tools/api-ledger availability api/10.11/foundation-manifest.txt . \
        --pin tests/api-10.11-annotations.txt

# the surface debt (what W2 inherits)
python3 ../libagora-app/tools/api-ledger missing api/10.11/foundation-manifest.txt . --library build/libagora-base.so

# the strict surface by hand
clang-19 -x objective-c -fobjc-runtime=gnustep-2.0 -fblocks -fsyntax-only -DAG_TARGET_OS_X_10_11 \
         -I build/agora-include -I ../build-prefix/include  probe.m

# the suites
cd build && ctest
```

---

## 7. Working-tree caveats

- **A concurrent editor is active** in this workspace (the same one the last two handoffs recorded). The libagora-base
  worktree was clean before this session and every edit was checked against `git status` before committing; the
  workspace's other dirty files are not this session's.
- The build tree's `agora-include/Foundation` is a **symlink to the source directory**, so header edits are visible to
  probes immediately — the gates and the hand measurements agree without an install step.
- `Testing/Temporary/*.log` are tracked (see §5); do not stage them.

---

## 8. Order I would take next

1. **W2: the missing 10.11 names** — the 21 classes and 99 selectors the census names. That is the surface the Cocoa
   plan promises, and it is now the only thing between this tree and §12.1's "zero unexempted missing names".
2. **Un-track the ctest logs** so a test run stops dirtying the tree.
3. **Then behaviour (M2)** per wave, with the four dispositions from the surface plan — not a name-only victory.
