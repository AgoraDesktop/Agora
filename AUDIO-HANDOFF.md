# AUDIO-HANDOFF — `libagora-audio`, state at the end of phase 5

For a fresh session picking this up. Read this, then `AUDIO-PLAN.md` (the design record) and
`libagora-audio/README.md` (the component's own contract). This file is the *state*; those are the *reasons*.

## 1. Where everything is, and what is green

| repository | HEAD | pushed | state |
|---|---|---|---|
| `libagora-audio` | see `git log -1` | no | clean; **14/14 tests, 0 warnings** on a clean configure; **needs committing** |
| `libagora-app` | `44eee74` | yes, `origin/main` | clean; **215/215 tests**; built against the new prefix |
| `release` | `66dba68` | no — 2 commits ahead | unchanged by phase 5b |
| workspace (parent) | `069dfa2` | no | `libagora-audio` gitlink will be behind again once this phase is committed |

**First action for the next session:** commit `libagora-audio`, then
`git -C ~/Development/Agora add libagora-audio` before the next parent commit, and advance the `release`
submodule pin when that repository is pushed. `git submodule status` must show no `-` for the components in
`components.conf` (`forge` and `libagora-webview` are currently uninitialised and are not in it).

`libagora-audio` is a submodule, sits **after `libagora-base`** in `release/components.conf`, and now links
`Foundation::Foundation` **PUBLIC** — which is the same reason it sits there, and only makes it more true.

## 2. The contract: macOS 10.12 is the specification

The API is **declaration-identical** to `MacOSX10.12.sdk`, not "inspired by" it:

- `tests/api/manifest-10.12.txt` is **generated** by `tools/api-manifest.py` from the reference headers and
  committed: **87 records, 1853 constants, 269 typedefs, 244 prototypes, 9 Objective-C classes, 43 methods**.
  The SDK itself is never committed.
- Five gates keep it true: `api-layout` (`_Static_assert` on every size/alignment/offset), `api-macros`
  (constant values), `api-prototypes` (every exported function through a pointer typed from the manifest),
  `api-cxx` (the doors under `-std=c++17`), and **`api-objc`** (every declared class, and each property and
  method's qualified type, by `__builtin_types_compatible_p`, built with `-Werror=objc-method-access` so a
  *removed* declaration fails the build too).
- `tools/refshim/` is ours (`TargetConditionals.h`, `Availability.h`, empty `MacTypes.h`, CF and dispatch
  *types*, two `mach` stubs, and — new in phase 5b — **Foundation's declarations only**). It is not installed.
- What identity does **not** cover: the include graph below our headers, and behaviour.

Regenerating the manifest (needs the SDK; `/tmp/refsdk` from the last session is gone after a reboot):

```sh
# stage a MacOSX10.12.sdk-like tree at /tmp/refsdk (System/Library/Frameworks/*.framework/Versions/A/Headers)
cd libagora-audio
python3 tools/api-manifest.py --sdk /tmp/refsdk --out tests/api/manifest-10.12.txt \
    CoreAudio/CoreAudioTypes.h CoreAudio/HostTime.h CoreAudio/AudioHardwareBase.h CoreAudio/AudioHardware.h \
    AudioToolbox/AudioFormat.h AudioToolbox/AudioConverter.h AudioToolbox/AudioFile.h \
    AudioToolbox/AudioFileStream.h AudioToolbox/ExtendedAudioFile.h AudioToolbox/AudioQueue.h \
    AudioToolbox/AudioServices.h AudioToolbox/AudioComponent.h AudioToolbox/AudioUnit.h \
    AudioToolbox/AudioOutputUnit.h AudioToolbox/AUGraph.h \
    AudioToolbox/AudioUnitProperties.h AudioToolbox/AUParameters.h AudioToolbox/AUAudioUnit.h
```

Tip: the headers come from the `phracker/MacOSX-SDKs` raw tree (`MacOSX10.12.sdk/...`). Fetch
`CoreAudio`, `AudioToolbox` and `AudioUnit` (52 files) with the GitHub contents API; `CoreAudioTypes` has no
framework directory of its own in that SDK. **Expect the diff to rewrite the scratch-directory paths** in six
`[record]` field lines (`/tmp/agora-api-*/stage/...`) — that churn is inherent and harmless.

## 3. What exists, door by door

| door | implemented | refused, by name |
|---|---|---|
| `CoreAudio/CoreAudioTypes.h` | the structures, time stamps, flag vocabulary, status codes, `AudioChannelLayout`/`AudioBufferList` variable-length traps | the full constant tables (the manifest holds them) |
| `CoreAudio/HostTime.h` | `clock_gettime(CLOCK_MONOTONIC)` scaled to 1e9 ticks/s; conversions invert | — |
| `CoreAudio/AudioHardware*.h` | the object model: 5 property functions, listeners (proc **and** block, wildcards), io procs, the in-process mixer, volume/mute/clock; **two backends** (`null` always, ALSA when `pkg-config alsa`) | `kAudioDevicePropertyBufferFrameSize` writes, deprecated doors are *translated*, not refused |
| `AudioToolbox/AudioFormat.h` | `FormatInfo`, `NumberOfChannelsForLayout`, `ChannelLayoutForTag`, `ValidateChannelLayout` | every other selector (`'prop'`) |
| `AudioToolbox/AudioConverter.h` | both calling models, 14 properties, format + rate (windowed-sinc, 32 taps) | non-PCM (`'fmt?'`), `ConvertBuffer` across a rate change |
| `AudioToolbox/AudioFile.h` | **WAV, AIFF, CAF** read/write with size patching; byte and packet doors | compressed formats, unknown containers, FSRef doors (not declared, on purpose) |
| `AudioToolbox/ExtendedAudioFile.h` | open/create/wrap, read/write/write-async, seek/tell, client format | — |
| `AudioToolbox/AudioFileStream.h` | incremental parse of the same three containers, listener + packet callbacks | `AudioFileStreamSeek` (`'nope'`) |
| `AudioToolbox/AudioQueue.h` | output queues: buffers, refilling callback (lock released), volume as a **parameter**, properties | input queues, timelines, taps, offline render |
| `AudioToolbox/AudioServices.h` | system sounds by URL + the **generated** alert (1.5 kHz decay) | properties (`'pty?'`) |
| `AudioToolbox/AudioComponent.h` | a registry of **three** built-ins; find/count/describe/copy-name/instance | any fourth thing (no plug-in ABI) |
| `AudioToolbox/AudioUnit.h` | `DefaultOutput`, `AUConverter`, `MultiChannelMixer`; properties, parameters, `AudioUnitRender`; **`ParameterList`/`ParameterInfo`, `AudioUnitParameterInfo`, the unit and flag vocabulary** | `AudioUnitProcess`, render notify, scheduled parameters |
| `AudioToolbox/AudioOutputUnit.h` | start/stop an output unit on the default device | — |
| `AudioToolbox/AUGraph.h` | nodes, connections, per-input callbacks, open/init/start/stop, cycle refusal | sub-graphs and the Carbon node doors (not declared) |
| `AudioToolbox/AUParameters.h` **(new)** | `AUParameterNode`/`Group`/`Tree`/`Parameter`, the three observer blocks, the implementor observer/provider pair, the `(Factory)` creation doors | `NSSecureCoding` (not claimed); the group-template doors (not declared) |
| `AudioToolbox/AUAudioUnit.h` **(new)** | `AUAudioUnit` (+ `AUAudioInputOutputUnit` category), `AUAudioUnitBus`, `AUAudioUnitBusArray`, `AUAudioUnitPreset`, the block vocabulary, `-renderBlock`, `-parameterTree`, `-startHardware`/`-stopHardware`, `-allocateRenderResources` | out-of-process instantiation (answers with an error), MIDI, presets/state, `AUAudioUnitFactory` and app extensions (not declared) |

Measured, as of the last green run: 44.1 k → 48 k SNR **85.2 dB**; int16 round trip **bit-exact**; WAV/AIFF/CAF
round trips `memcmp`-exact; the null backend renders **12 000 frames in 250 ms** (±20% band); two io procs
0.25 + 0.125 mix to **0.375**; a queue, a unit and a graph each reach the device at the value they were given;
mute mixes **0.0**; through AUv3, two buses at volumes 1.0 and 0.25 mix **0.28125**, and a tree write lands in
`AudioUnitGetParameter`.

### The three things about AUv3 that are not Apple's

1. **A bus's format is an `AudioStreamBasicDescription`**, not an `AVAudioFormat *`. AVFoundation is
   deliberately absent from this component (`AUDIO-PLAN.md` §5); a forward-declared `AVAudioFormat` would be
   a type no client here can construct.
2. **`AUParameterAddress` encodes the C coordinates**: `scope << 32 | element << 16 | id`, because a v2
   parameter is three numbers and an address is one. `-parameterWithID:scope:element:` takes them apart. A
   `keyPath` is the tree's other naming: ancestors' identifiers joined by dots, and a tree's own is empty.
3. **No `NSSecureCoding`** on the parameter classes or `AUAudioUnitPreset` (there is no coder; the conformance
   would be a promise `-encodeWithCoder:` cannot keep), and **no out-of-process loading**.

## 4. Build and test

```sh
C=/usr/bin/clang-19
cmake -S libagora-audio -B libagora-audio/build -DCMAKE_C_COMPILER=$C \
      -DCMAKE_CXX_COMPILER=/usr/bin/clang++-19 \
      -DCMAKE_OBJC_COMPILER=$C \
      -DCMAKE_PREFIX_PATH=$PWD/build-prefix -DCMAKE_INSTALL_PREFIX=$PWD/build-prefix
cmake --build libagora-audio/build -j"$(nproc)"
ctest --test-dir libagora-audio/build --output-on-failure     # 14 tests, ~3 s
```

Through the federation: `"$HOME/.agents/skills/agora-desktop/scripts/agora-build.sh" --only libagora-audio --test`
(both scripts already pass `-DCMAKE_OBJC_COMPILER`).

- `-DBUILD_TESTING=OFF` builds no test target at all (what the release driver passes).
- `-DAGORA_AUDIO_WITH_ALSA=OFF` drops the ALSA backend; the HAL falls back to the null device.
- The ALSA leg runs the same `hal` suite against ALSA's `null` PCM (`hal-alsa`); it skips only the pacing
  assertion.
- Suites state their backend in code (`fn_agora_audio_set_driver`, `AudioToolbox_internal.h`).

## 5. Traps already paid for — do not pay twice

1. **`snd_pcm_uframes_t` is `unsigned long`.** Handing ALSA the address of a `UInt32` field writes eight bytes
   into a four-byte slot: no compile error, then a glibc `malloc` assertion three frames later.
2. **A queue buffer that ends exactly on a quantum boundary** left every other device quantum silent when the
   render loop `break`s; it must hand the buffer back and keep filling.
3. **`AudioServicesPlaySystemSound` deadlocked** on its own non-recursive lock. Callbacks and lock acquisition
   never nest.
4. **The graph's cycle check walked connections backwards**, found no ring, installed one, and the pull
   recursed until the stack ran out. Ask "does the destination already reach the source".
5. **AIFF's 80-bit sample rate**: `mantissa * 2^(exponent − 16383 − 63)`; wrong bias reads 48000 as 0.73 Hz.
6. **`__nonnull` is glibc's function attribute.** The reference parse rewrites Darwin's spelling in a scratch
   copy; our headers use `_Nonnull`/`_Nullable`.
7. **`CF_ENUM` in Core Foundation's C fallback form** is what Apple compiles in C.
8. **Constants the manifest corrected**: `'acid'`/`'acod'`; audio-file unsupported property is `'pty?'`; **no**
   `kAudioFilePropertyFileLengthFrames` in 10.12; **no** `kAudioUnitErr_InvalidPropertySize` (use `-10851`);
   `AudioDeviceIOProcID` *is* `AudioDeviceIOProc`; `inInputTime` is not nullable. New: `'atyp'`-style
   **parameter ids are not property ids** — `kAudioUnitProperty_ParameterInfo` is **4**, not 53, and the
   *element* of that query is the parameter id.
9. **`libagora-app` is MRR, not ARC**, its sources are globbed, and its two census ledgers must be edited
   **deliberately** when the AppKit surface changes.
10. **`LD_LIBRARY_PATH` order**: the installed prefix shadows a fresh build. Put the component's `build`
    directory first, and `ldd` what actually loaded.
11. **`-fobjc-arc` is refused on this runtime** ("not supported on platforms using the legacy runtime"), so
    every Objective-C file in this tree is manual retain/release, and a block that is stored is
    `Block_copy`'d and `Block_release`'d by the object that stored it. A block that captures `self` is a leak
    with no way out: `AUAudioUnit`'s render block captures the **`AudioUnit` pointer**, not the object.
12. **`project(AgoraAudio LANGUAGES C OBJC)` needs `-DCMAKE_OBJC_COMPILER`** or CMake picks `cc` and gcc
    answers `cannot execute 'cc1obj'`. The federation scripts pass it; a hand-written configure must.
13. **The manifest generator now reads as Objective-C** (`-x objective-c -fobjc-runtime=macosx-10.12`), which
    is what makes `#if __OBJC2__` true and is the only way to read `AUParameters.h`. The consequence is that
    C headers are measured **as an Objective-C client sees them**: `#if __OBJC__` doors (the
    `AURenderEvent` family, `AudioComponentGetIcon` returning `NSImage *`) are now in the manifest, and were
    not before.
14. **clang's JSON omits `file` whenever a node repeats the previous node's file.** The ObjC facts read the
    file from the same source-order `walk` the C facts use (indexed by node id), not from a recursive
    `loc`-only descent — that descent finds no file for the children of the first declaration in a header.
15. **A struct with an interior pointer cannot be returned by value.** The `auv3` suite's `fn_storage` fills
    a `render_storage` **in place**; returning one would leave `mBuffers[0].mData` pointing at the samples of
    a dead stack frame, and the render would write to nothing while the test read zeros.

## 6. Next work, in the order the plan argues for

### (a) PipeWire backend

The seam is already there: `agora_driver` in `AudioToolbox_internal.h` (describe devices, start, stop) and
`fn_agora_device_render`. A PipeWire driver describes the registry's devices, opens a stream in its process
callback and calls `fn_agora_device_render`. Add `-DAGORA_AUDIO_WITH_PIPEWIRE`, the `libpipewire-0.3`
pkg-config name (not `pipewire-0.3`), a `hal-pipewire` test leg against a live server, and
`AGORA_AUDIO_DRIVER=pipewire`. This machine has PipeWire 1.4.2 running with four playback devices, so it is
measurable.

### (b) `libagora-app`'s remaining audio TODOs

- **A suite for `NSSound`** (it has none): `-duration`, `-isPlaying` after `-play`, `-loops` re-enqueue,
  `-stop`, `+soundNamed:`, `NSSoundDelegate`. Follow the census-edit rule in §5.9.
- `NSBundleAdditions.h` still owes its **header split**: `-pathForSoundResource:` belongs in `NSSound.h`.
- `NSButtonCell.m` still excludes `_sound` from archiving "because this tier does not ship `NSSound`".
- `COCOA-10.11-SURFACE-PLAN.md` A5: the `NSSound` row says "refused or adapted"; it is implemented now.

### (c) Smaller, in the plan's own order

- `sndio` backend for the BSDs (`AudioHardware-sndio.c`), labelled **written, not measured** until a BSD run.
- `CoreMIDI` stays out of this component; a `libagora-midi` if one appears.
- `AudioQueue`'s input side, timelines, taps; `AUGraph` sub-graphs; the remaining `AudioFormat` selectors.
- AUv3's remaining optional doors, each a real question rather than a stub: `-fullState`/`-factoryPresets`
  need a state serialisation the C side does not have; MIDI needs a device class this component does not
  ship. Both are nil today and said so in the README.

## 7. Open decisions

1. **`AUAudioUnitBus.format` vs `AVAudioFormat`.** Settled the only way it can be without AVFoundation: a bus
   carries an `AudioStreamBasicDescription`. If `libagora-avfoundation` ever appears, this is the header to
   revisit — and the `auv3` suite is where the change will show.
2. **Volume on the device vs on the queue/unit**: both exist and multiply today. Apple's HAL volume is per
   device; this is consistent, but worth stating in the README when the next audio door lands.
3. **`AudioServices` one-queue reuse**: a second alert restarts the queue. If an app needs overlapping system
   sounds, that is the place to look.
4. **Where `AUDIO-PLAN.md` lives long-term**: it is committed at the workspace root; the component's README has
   taken over the current-state job. Phase 5 is closed now, so the plan can be folded into the component.
