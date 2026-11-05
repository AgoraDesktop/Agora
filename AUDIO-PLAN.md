# AUDIO-PLAN — `libagora-audio`, the Core Audio equivalent

**A plan, not a record: nothing here is measured yet.** It is written the way `libagora-watch` was — against
Apple's model — with one difference that governs everything below: **the API is not "Apple's model", it is
macOS 10.12's API, declaration for declaration.** Once the repository exists this file is deleted, and what
survives contact with the compiler moves into `libagora-audio/README.md` and `libagora-audio/DESIGN.md`.

Every prototype, constant and size named in this document is **provisional**. The reference SDK settles it
(§1.1) and the conformance manifest (§1.2) wins over this file.

## 1. The specification: macOS 10.12, declaration-identical

"Identical" is a checkable list, and each item has a way to fail:

| identity | example | how it fails |
|---|---|---|
| symbol names | `AudioQueueNewOutput`, `kAudioFormatLinearPCM` | a typo, or an `Agora` prefix |
| types, including spelling | `AudioStreamBasicDescription`, `OSStatus`, `UInt32` | `int` where Apple says `SInt32` |
| prototypes | parameter types, `const`, nullability, return type | `AudioFileOpenURL(…, AudioFileID * outID)` losing `_Nullable` |
| enumerator and constant **values** | `kAudioFormatFlagsNativeFloatPacked`, four-char codes | a renumbered enum; a mistyped `'lpcm'` |
| structure layout | field order, widths, alignment, flexible members | `AudioBufferList` off by its `mBuffers[1]` |
| compile-time macros | `AudioFormatFlagsIsSignedInteger`, `IsAudioFormatFlagsNativeEndian` | an expression that differs for one flag pattern |
| availability decorations | `API_AVAILABLE(macos(10.12))`, `API_DEPRECATED` | a deprecated door that reads as current |
| include path | `<CoreAudio/AudioHardware.h>`, `<AudioToolbox/AudioFile.h>` | a consumer's `#import` failing |
| language linkage | `extern "C"` guards | a C++ consumer failing to link |

Two things are *not* part of identity, and the plan says so out loud: the **include graph below our headers**
(Apple's `CoreAudioTypes.h` reaches `MacTypes.h`; ours reaches `CoreFoundation/CFBase.h`, which already defines
`OSStatus`, `SInt32`, `UInt32`, `Boolean` — measured: `libagora-core/include/CFBase.h:87`), and the **values
computed at runtime**, which are behaviour, not API (§1.3).

### 1.1 Where the reference lives, and why it is not in the repository

The declarations come from `MacOSX10.12.sdk` — an Xcode 8.2/8.3 install, or an archived copy of one. That SDK
is **never committed**. Apple's headers are copyrighted, so the repository carries our own written
declarations and a generated *manifest of facts* — names, values, offsets — which is what the tree already does
for Core Foundation, Core Graphics and AppKit. The difference here is that until now nobody checked.

- `AGORA_COREAUDIO_SDK=/path/to/MacOSX10.12.sdk` is read by a generator (`tools/api-manifest.sh`).
  **This machine has no SDK (measured: no `*.sdk` anywhere), but the reference is obtainable and the pipeline
  is proven here** — see §1.5.
- The generator emits `tests/api/manifest-10.12.txt` with `clang -fdump-record-layouts` for every structure
  and an AST dump for every declaration, and the manifest **is** committed. It is the specification the
  headers are typed from, and the thing the suite checks them against.
- If no SDK can be obtained, phase 0 does not start. That is a hard prerequisite, and it is stated as a
  prerequisite rather than discovered in phase 3.

### 1.2 How identity is proven, on every `ctest`

Three mechanisms, all cheap, all in the default leg:

1. **`tests/api/layout.c`** — `_Static_assert` on `sizeof`, `alignof` and `offsetof` for every public structure,
   against the numbers in the manifest. `AudioBufferList`, `AudioChannelLayout`, `AudioTimeStamp`, `SMPTETime`,
   `AudioStreamBasicDescription`, `AudioStreamPacketDescription`, `AudioComponentDescription`,
   `AudioObjectPropertyAddress`, `AudioBuffer`, `AudioClassDescription`, and the AUv3 parameter structs.
   These are the types where a wrong layout is silent corruption in a client, not a compile error.
2. **`tests/api/prototypes.c`** — a translation unit that takes, for **every** declared function, the address
   into a function pointer written from the manifest's prototype. A changed parameter, a dropped `const`, a
   changed return type is a compile error in two places at once, and the file is never executed.
3. **`tests/api/macros.c`** — the flag-decoding macros are compile-time, so they are checked by *value*: for
   every interesting bit pattern, the macro's result equals the recorded one. A macro that is right for
   `kAudioFormatFlagsNativeFloatPacked` and wrong for a big-endian packed integer is a real bug this catches.

Plus `tests/api/compile-cxx.cpp` (the headers under `extern "C"` and `-std=c++17`) and `tests/api/refuse.c`,
which asserts that each Tier B door (§1.3) returns the documented error rather than crashing or lying.

### 1.3 Fidelity is graded; identity is not

Identity applies to **declarations**. Behaviour is graded, explicitly and per door, and the README carries the
table so no reader has to guess which is which:

- **Tier A — implemented and measured.** Formats, converter, files (WAV/AIFF/CAF), `ExtAudioFile`, the HAL, the
  device objects and IOProcs, `AudioQueue`, `AudioServices`, `AudioUnit` (built-in units), `AUGraph`.
- **Tier B — declared, refusing with the documented status.** `AudioCodec` (10.5's codec components),
  `AudioFileComponent`, `AudioHardwareService`, `AudioHardwareDeprecated`, `MusicPlayer`/`MusicSequence` until
  phase 6, the `AudioHardwareTuning` doors we cannot honour without owning the device. They exist, they are
  callable, and they return `kAudioHardwareUnsupportedOperationError` / `kAudio_ParamError` / `kAudioFileUnsupportedFileTypeError`
  as the header documents — **with a one-shot diagnostic**, the same shape as AppKit's `fn_refuse_window`, and
  the same rule: a refusal that says what is missing instead of pretending.
- **Tier C — declared, and documented as not loadable by us.** `AudioComponentFindNext` finds only the
  registered built-ins plus anything the process itself registered through `AudioComponentRegister`, because
  loading a third-party `AudioComponent` means honouring a foreign binary ABI. The declarations are identical;
  the registry is ours.

**Behaviour fidelity is not measured against a macOS run**, because there is no macOS here. It follows the
header's documented semantics, and every behavioural test names the sentence it is checking. The README says
that in those words rather than implying a differential test that does not exist.

### 1.4 Version skew, stated once

The tree's Cocoa surface targets 10.11 (`COCOA-10.11-SURFACE-PLAN.md`); Core Audio is 10.12. The difference is
not cosmetic: **AUv3 (`AUAudioUnit`, `AUParameterTree`, `AUAudioUnitFactory`) arrived in 10.12**, so it is *in*
this surface while AppKit stays 10.11. Consequence: this component is **`LANGUAGES C OBJC`**, not C only, and
the ObjC door is the plug-in-facing one. AppKit's `NSSound` is unrelated to any of this and stays 10.11-shaped.

**AND IT IS WHY THIS COMPONENT CANNOT SIT BELOW FOUNDATION.** Measured from the 10.12 headers themselves:
`AudioToolbox/AUParameters.h` line 13 is `#import <Foundation/Foundation.h>`, and `AUAudioUnit.h` also imports
`<Foundation/NSExtensionRequestHandling.h>`. So `libagora-audio` resolves `Foundation` (`find_package(Foundation
CONFIG)`) and stands **after `libagora-base`** in `release/components.conf` — not after `libagora-core` as an
earlier draft of this plan said. The alternative, keeping audio below Foundation, means AUv3 becomes a second
component above it; occupying one repository's worth of types twice is the worse trade.

### 1.5 The pipeline is proven here, not assumed

Run on this Linux machine against the 10.12 SDK header tree, with `/usr/bin/clang-19` and a **committed shim tree
(`tools/refshim/`, our own text, ~60 lines)**:

- `CoreAudio/CoreAudioTypes.h`, `CoreAudio/AudioHardwareBase.h`, `CoreAudio/HostTime.h` and
  `AudioToolbox/AudioQueue.h` (92 KB) each parse to **0 errors**; `AudioHardware.h` parses once
  `AudioHardwareDeprecated.h` is fetched, with `-fblocks` for its block-based listeners.
- What the shim has to supply, and nothing more: `TargetConditionals.h`, `Availability.h`, an empty
  `MacTypes.h`, Core Foundation's **types only**, dispatch's **types only**, `mach/port.h` and
  `mach/machine.h` stubs, `__nonnull`/`__nullable` rewritten to `_Nonnull`/`_Nullable` by the generator's copy
  step (Darwin's cdefs keyword is *glibc's function attribute* here — the one real portability trap), and
  `CF_ENUM`/`CF_OPTIONS` in CoreFoundation's own C fallback form (`_type _name; enum`), which is what Apple
  compiles in C anyway.
- `clang -Xclang -fdump-record-layouts-complete` then yields the manifest's numbers directly. For
  `AudioStreamBasicDescription` it reports `sizeof=40, align=8` with `mSampleRate` at 0, `mFormatID` at 8,
  `mFormatFlags` at 12, and the five `UInt32` fields at 16/20/24/28/32, `mReserved` at 36 — a real line of the
  manifest, generated today, not remembered.

Two 10.12 facts the enumeration settled: **`CoreAudioTypes` is a header inside `CoreAudio.framework` in 10.12**
(a `CoreAudioTypes.framework` path 404s) so there is no fourth door; and **`AudioUnit.framework`'s headers are
flat inside `AudioToolbox.framework`** in this SDK (its own `AudioUnit.h` is a 36-byte stub), while clients still
`#import <AudioUnit/…>` — so the install path stays `<AudioUnit/…>` and the reference parse maps it there.

## 2. What is being built, and what is not

On macOS the family is four frameworks over a driver model. Three of them are this component; the fourth is a
sibling framework, not part of Core Audio, and is not this component.

| framework | what it is | here |
|---|---|---|
| `CoreAudio` | the HAL: devices as objects with properties, IOProcs, listeners, host time | **this repo** |
| `AudioToolbox` | formats, files, streams, converter, queues, services, components, units, graph, music player | **this repo** |
| `AudioUnit` | the unit surface, properties, output units, AUGraph, AUv3's C half | **this repo** |
| `CoreMIDI` | endpoints, packets, virtual sources | **not here** — `libagora-midi`, if an app ever needs one |

**It is a client of the session's sound server, not a sound server.** PipeWire (or ALSA, or sndio) owns the
device; this library is a client with an Apple-shaped face. The same line the compositor draws: the window
server composites, it does not drive a display.

### Deliberately absent, each for a reason

- **No `AVFoundation`** (`AVAudioPlayer`, `AVAudioEngine`, `AVAudioSession`). A media framework above this one
  when it is wanted — `libagora-avfoundation`. Out of Core Audio proper.
- **No compressed codecs** (MP3, AAC, FLAC, ALAC, Opus): nothing on this machine provides a permissively
  licensed decoder as a *system* library and vendoring code is not allowed. `AudioFileOpenURL` and
  `AudioFileStreamOpen` return the documented unsupported-format status, and the suite measures that.
- **No effects or synthesis beyond the alert tone.** No reverb, no EQ, no `AUSampler`, no DLS, no speech.
  `NSBeep` needs one sound, and it is **generated** (a short decaying tone) rather than vendored, so the
  installation carries no unlicensed audio.
- **No hardware configuration.** The HAL never changes a device's sample rate or frame size; it adopts what the
  device reports and resamples, which is behaviour the header permits and a shared desktop needs.
- **No second API.** Everything Apple-shaped lives behind the three doors; the Agora-only bits — the driver
  override, the diagnostics — live in headers excluded from the install and never enter a door (§4).

## 3. Where it sits

- **Repository**: `libagora-audio`, submodule at `https://github.com/AgoraDesktop/libagora-audio.git`, branch `main`.
- **Order** in `release/components.conf`: **immediately after `libagora-base`**, because 10.12's AUv3 headers
  import Foundation (§1.4). It resolves `Foundation` and `dispatch` (PUBLIC) — AppKit's `NSSound` is above it —
  plus system audio libraries (PRIVATE).
- **Licence**: LGPL-3.0-or-later for the library, GPL-3.0-or-later for `tests/` — the same per-artifact split as
  every other library, forced by the same fact (`libagora-core`/`libagora-dispatch` are Apache-2.0, which
  resolves with 3.0 and not 2.1). System libraries are compatible: PipeWire MIT, sndio ISC, libasound LGPL-2.1
  **dynamically linked only**.
- **Inside the workspace README's table**: a row in *the Cocoa stack*, beside Core Graphics and Core Text —
  below AppKit, above Foundation only because 10.12's own headers demand it; AppKit's `NSSound` links it.
- One library, one `.so`, three include doors (`<CoreAudio/…>`, `<AudioToolbox/…>`, `<AudioUnit/…>`), one
  `find_package(AgoraAudio CONFIG)`. Apple ships frameworks; nothing else in this tree does, and a framework
  bundle would be a second installation convention for no gain. Consumers link `AgoraAudio::Audio`.

## 4. The device seam, and the four backends

One internal vtable, `AgoraAudioDriver` (`AudioHardware_internal.h`, excluded from the install), is the whole
platform story: enumerate devices, open one, run a stream whose callback fills or drains the mixer's buffer,
report volume/mute/rate, post "devices changed". Everything above it is portable C.

| backend | platform | library | licence | measured here? |
|---|---|---|---|---|
| `pipewire` | Linux | `libpipewire-0.3` 1.4.2 | MIT | **yes** — installed, a server is running, four playback devices reported (USB AudioBox, HDA Analog, two HDMI) plus capture |
| `alsa` | Linux | `alsa` 1.2.14 | LGPL-2.1 (dynamic) | **yes** — `/dev/snd` playback nodes; tested against the `null` PCM, the `pipewire` PCM and real hardware |
| `sndio` | FreeBSD, NetBSD, OpenBSD | `sndio` 1.10.0 | ISC | **written, not run** — labelled so, exactly as `EventStream-kqueue.c` is |
| `null` | every platform | none | — | **yes** — always compiled in; the deterministic sink and source the suite measures |

- **PipeWire preferred, ALSA the floor, `null` always.** Both Linux backends compile when their dev packages
  exist (`-DAGORA_AUDIO_WITH_PIPEWIRE=AUTO|ON|OFF`, same for ALSA and sndio) and the choice between them is made
  **at runtime**, because a build-time choice cannot run on a machine with no session server and CI has no sound
  card. (`libagora-watch` chooses at build time because inotify and kqueue cannot share one binary; two audio
  clients can.)
- **The choice is not part of the API.** Apple's client-facing answer is "set the default device"; ours is the
  same, plus a *test and debug* environment variable `AGORA_AUDIO_DRIVER` and a private header function
  `fn_agora_audio_set_driver()` so a suite states its backend in code and a developer's shell cannot change what
  a test measured. Precedent: the `APPKIT_*_DIAG` variables and `--backend` on the compositor — and, like them,
  it is invisible to a consumer reading `<CoreAudio/CoreAudio.h>`.
- **ALSA is opened by name, never `hw:`** (`default`, `plug`, or `AGORA_AUDIO_ALSA_PCM`, `null` in tests): direct
  hardware access is exclusive, and `dmix`/PipeWire's ALSA door exist so a desktop keeps making sound.
- **The mixer is in the HAL, not in the backend.** PipeWire mixes, ALSA-`hw` does not, `null` does not, and the
  HAL must behave the same in all three: N clients on one device are summed in-process (f32, per-client volume,
  saturating) and one backend stream carries the result. Apple's HAL mixes too, so this is fidelity as well as
  simplicity — and it is what makes "two IOProcs on the default device" testable at all.
- **Nothing allocates on the audio thread.** The backend's data thread calls a lock-free SPSC ring; allocation
  and `CFString` happen when a client attaches, never while it plays.

## 5. Threading and time

- The IOProc runs on **the backend's data thread** (PipeWire's process thread, ALSA's blocking `write` loop, the
  `null` backend's own thread). The README says so, as `libagora-watch` says the callback runs on the reader
  thread.
- Block-based property listeners dispatch on a `dispatch_queue_t` through `libagora-dispatch`; the older
  function-pointer form dispatches on a serial queue. Both are 10.12-declared and both are real.
- `AudioGetCurrentHostTime` / `AudioConvertHostTimeToNanos` / `AudioGetHostClockFrequency` are
  `clock_gettime(CLOCK_MONOTONIC)` scaled to Apple's frequency; `AudioDeviceGetCurrentTime` reports the last
  frame's host time from the ring's read position, so playback position is a measurement, not a guess.

## 6. The doors, by header

The header **set** is whatever 10.12's three frameworks ship — enumerated by the manifest, not by memory. What
this plan commits to is the implementation, per header family, and the tier:

| header family (10.12 spells confirmed by the manifest) | door | tier | phase |
|---|---|---|---|
| `CoreAudio/CoreAudioTypes.h` (inside `CoreAudio.framework` in 10.12) — `AudioStreamBasicDescription`, `AudioChannelLayout`, `AudioTimeStamp`, `SMPTETime`, the format flags and their macros | CoreAudio | A | 0 |
| `AudioFormat.h` — `AudioFormatGetProperty`, converter-independent format questions | AudioToolbox | A | 1 |
| `AudioConverter.h` — `AudioConverterNew`, `AudioConverterFillComplexBuffer`, properties, `Reset` | AudioToolbox | A | 1 |
| `AudioFile.h` + `CAFFile.h`/`AudioFile` chunk files — open/read/write/packets/properties | AudioToolbox | A (WAV/AIFF/CAF) | 1 |
| `AudioFileStream.h` — the incremental parser (`ParseBytes`, `ParseData`, properties) | AudioToolbox | A for the three containers | 1 |
| `ExtendedAudioFile.h` — client-format reads and writes through the converter | AudioToolbox | A | 1 |
| `CoreAudio/AudioObject.h` — `AudioObjectID`, `AudioObjectPropertyAddress`, `Get/Set/Has/AddListener` | CoreAudio | A | 2 |
| `CoreAudio/AudioHardware.h` — devices, streams, IOProcs, `AudioDeviceStart/Stop`, default device, listeners | CoreAudio | A | 2 |
| `CoreAudio/HostTime.h` — host clock and its conversions | CoreAudio | A | 2 |
| `CoreAudio/AudioHardwareDeprecated.h`, `AudioHardwareService.h` | CoreAudio | **B** | 2 |
| `AudioQueue.h` — `AudioQueueNewOutput/WithDispatchQueue`, buffers, timing, properties | AudioToolbox | A | 4 |
| `AudioServices.h` — alert and system sounds, `CreateSystemSoundID`, completion blocks | AudioToolbox | A | 4 |
| `AudioUnit/AudioUnit.h`, `AudioUnitProperties.h`, `AudioUnitUtilities.h`, `AudioOutputUnit.h` — the unit surface, `AudioUnitRender`, the render callback, scopes and elements | AudioUnit | A | 5 |
| `AudioComponents.h` — `AudioComponentDescription`, `FindNext`, `InstanceNew`, `Register`, `CopyName` | AudioToolbox | A (registry is ours) | 5 |
| `AudioUnit/AUGraph.h` — nodes, connections, render | AudioUnit | A | 5 |
| `AUAudioUnit.h`, `AUParameters.h` — AUv3's object surface, `AUParameterTree` (imports Foundation; see §1.4) | AudioToolbox | A (in-process), third-party hosting refused | 5 |
| `MusicPlayer.h`, `MusicSequence.h`, `MusicTrack?` — the sequencer | AudioToolbox | **B** until phase 6 | 6 |
| `AudioCodec.h` (57 KB), `AudioFileComponent.h`, `AudioHardwareTuning.h` | — | **B** | — |

Tier B is not free: `AudioCodec.h` alone is 57 KB of declarations and `MusicPlayer.h` 65 KB. The manifest records
them from day one; the transcription is scheduled with the phase that first needs to refuse them.

`CoreMIDI.framework` (`<CoreMIDI/…>`) is **not** here: it is a sibling framework with its own device class
(rawmidi, not PCM). If a synthesiser appears it becomes `libagora-midi`, sharing the format and host-time
types and nothing else.

## 7. What the suite measures (headless first)

The compositor's rule applies: **a test that needs a sound card is opt-in.** The default leg runs on `null`
and, where ALSA exists, on a `plug`/`null` PCM; nothing in it depends on hardware, a session server, or anyone
being able to hear anything.

| test | what it asserts |
|---|---|
| `api-layout`, `api-prototypes`, `api-macros`, `api-cxx`, `api-refuse` | §1.2: identity of every size, offset, prototype, macro result, C linkage — and that Tier B refuses with the documented status |
| `audio-format` | flag decoding and ASBD validation against the header's own rules, including structures that must be refused |
| `audio-converter` | a 1 kHz sine at 44.1 k → 48 k measured for frequency and SNR (a number, not "it ran"); interleave/de-interleave and i16↔f32 bit-exact |
| `audio-file` | a known tone written and read back **bit-exactly** as WAV, AIFF and CAF; the format property reports what was written; MP3/FLAC refused with the documented error; the same files through `AudioFileStream`'s incremental parser |
| `audio-hal` | on `null`: an IOProc is called at the device's rate for N frames within a wall-clock tolerance; volume/mute round-trip; a listener fires on default-device change; **two IOProcs sum** (sample values, not a flag) |
| `audio-queue` | ten enqueued buffers arrive in order and complete; a stop that drains does; an immediate stop does not |
| `audio-unit` | the default-output unit renders a known oscillator through `AudioUnitRender` at the right frame count; a three-node `AUGraph` produces the same samples as the direct path |
| `audio-live` | **opt-in (`AGORA_AUDIO_LIVE=1`)**, otherwise 77: 100 ms on the real default device, asserting consumed frames; on PipeWire also asserting the node appeared in `pw-dump`. Same rule as the nested pixel runners. |

Cheap and printed in the README, like `libagora-watch` prints its `NEEDED` list: `readelf -d` on the installed
`.so` shows only `libagora-core.so`, `libagora-dispatch.so`, the enabled backend libraries and `libc`.

## 8. Wiring changes in other repositories

Each is its own commit in its own repo, in this order, because each is what makes the previous one visible:

1. **`libagora-app` — `NSSound`** (AppKit's class, not Core Audio's): `-initWithContentsOfFile:byReference:`,
   `-initWithData:`, `-play`, `-stop`, `-pause`, `-isPlaying`, `-loop`, `-volume`, `-duration`, `NSSoundDelegate`,
   `+soundNamed:` — over `AudioFileOpenURL` + `AudioConverter` + `AudioQueue`, which is how Apple's does it. This
   closes three TODOs that already name it: `NSBundleAdditions.h` ("the split can happen when a real `NSSound`
   arrives" — move `-pathForSoundResource:` into `NSSound.h`), `NSButtonCell.m` (which excludes `_sound` from
   archiving because the class does not exist), and `NSPasteboard.h`'s `NSSoundPboardType`, which has no consumer.
2. **`libagora-app` — `NSBeep`**: `NSGraphics.m` stops refusing (drop its entry from "the six refusals") and
   calls `AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert)`.
3. **`COCOA-10.11-SURFACE-PLAN.md`**: the A5 row that lists `NSSound` as "refused or adapted" becomes
   "implemented over `libagora-audio`", with the phase that made it true.
4. **`README.md`** (component row and dependency diagram), **`.gitmodules`**, **`release/components.conf`**.
5. **`~/.agents/skills/agora-desktop`**: the dependency order, and this plan's successor in the "where to look"
   table, so the next agent finds the audio component without searching.
6. Nothing in `demo/`: a session is silent unless something asks it not to be.

## 9. Phases, each with an exit criterion

| phase | what is built | done when |
|---|---|---|
| **0 — skeleton and the specification** | repo, `.gitmodules`, `components.conf`, CMake (`$ORIGIN` runpath, `find_package(AgoraAudio CONFIG)`, `LANGUAGES C OBJC`), LICENSE/COPYING/COPYING.LESSER, README, PROVENANCE, `tools/refshim/` + the generator and `tests/api/manifest-10.12.txt`, the `CoreAudioTypes` door with its layout/macro asserts, the `null` driver | the manifest is generated from the reference and committed; `api-layout`/`api-macros`/`api-cxx` green; `agora-build.sh --only libagora-audio --test` green; `ldd` shows only allowed libraries |
| **1 — data, no device** | `AudioFormat`, `AudioConverter` (our own resampler), `AudioFile` (WAV/AIFF/CAF), `AudioFileStream`, `ExtAudioFile`, their prototypes and Tier B refusals | bit-exact round trip through all three containers; 44.1→48 measured; refusals measured; `api-prototypes` covers every implemented door |
| **2 — the HAL on `null` and ALSA** | object model, properties, listeners, IOProc, mixer, `HostTime`, the deprecated doors as Tier B | `audio-hal` green on `null`; the same suite green with `AGORA_AUDIO_DRIVER=alsa` against a `plug`/`null` PCM; `api-refuse` green for the deprecated doors |
| **3 — PipeWire** | the same HAL, one more file | `audio-hal` green on `pipewire` in this machine's session; `audio-live` shows the node in `pw-dump` |
| **4 — queues, alerts, `NSSound`** | `AudioQueue`, `AudioServices` + the generated alert tone, then the `libagora-app` wiring above | a real beep on the desktop; AppKit's suite still green; `NSSound` plays a WAV in a test |
| **5 — units, graph, AUv3** | `AudioComponents` registry, `AudioUnit` core, `AudioOutputUnit`, `AUGraph`, `AUAudioUnit`/`AUParameterTree` over it, a demo binary playing a sine through three units | `audio-unit` green; the demo audible on a real device; a process-registered unit is found by `AudioComponentFindNext` and a foreign `AudioComponent` is refused |
| **6 — music player, then the BSDs** | `MusicPlayer`/`MusicSequence` over the graph and the file layer; `AudioHardware-sndio.c` | a sequence plays; a BSD run turns "written" into "measured" — until then the README says which |
| **7 — only if an app asks** | `libagora-midi` (CoreMIDI over ALSA rawmidi / PipeWire Midi), `libagora-avfoundation` | their own plans |

Rough size, to keep the phases honest: phase 0—1 ≈ 3 k lines of C (of which the doors are declarations), 2—3 ≈
1.5 k, 4 ≈ 1.0 k, 5 ≈ 2.5 k, 6 ≈ 1.5 k, tests ≈ 2 k. That is several times `libagora-watch` (615 lines of C, 825
with headers, three backends) and closer to `libagora-drawing`: matching a whole framework's declarations is the
bulk of it, and the manifest is what keeps that bulk honest.

## 10. Decisions this plan proposes, and the arguments

1. **Identity over invention.** Where Apple's header says something we would have done differently, the header
   wins; where we cannot implement it, the symbol still exists and refuses with the documented status. A
   missing symbol is a worse lie than a refusal, because it cannot be checked.
2. **One repo, three doors.** `CoreAudio`, `AudioToolbox` and `AudioUnit` share `AudioStreamBasicDescription`,
   the status codes and the device; splitting them would install three copies of the types Apple's clients
   assume are one.
3. **Identity is proven mechanically, not by review.** The manifest plus three compile-time tests cost minutes
   to run and are the only way "identical to 10.12" stays true after the first year of edits.
4. **PipeWire, with ALSA as the floor.** PulseAudio's native API is the older client for the same server;
   ALSA is what a machine with no session server still has.
5. **Runtime backend choice, unlike `libagora-watch`'s build-time one** — argued in §4, and kept out of the API.
6. **A generated alert tone, not a vendored sound** — one asset smaller, no licence to track, and it makes
   `NSBeep` testable by value.
7. **`AUGraph` and AUv3 are in**, because 10.12 has them; **third-party `AudioComponent` loading is out**, because
   a foreign binary ABI is a promise this tree has not made anywhere else.
8. **`CoreMIDI` is not part of Core Audio** and does not ride along — no consumer in this tree, a different
   device class, and twice the platform story for nothing. (This machine has `/dev/snd/seq` and PipeWire
   publishes a BLE MIDI node, so the phase is measurable when it is wanted; that is not a reason to build it now.)
9. **Above Foundation, because the reference says so.** AUv3's headers import Foundation, so the layering is
   Apple's rather than the tidier one: `libagora-base` → `libagora-audio` → AppKit. Recorded here because a
   later reader will otherwise wonder why an audio library needs `NSString`.
10. **The reference shim tree is committed; the reference is not.** `tools/refshim/` is our own sixty lines and
    makes the generator reproducible by anyone holding an SDK; `MacOSX10.12.sdk` itself stays outside the
    repository, because the manifest of facts is what we publish, not Apple's text.
