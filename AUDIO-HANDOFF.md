# AUDIO-HANDOFF — `libagora-audio`, state at the end of phase 5's C half

For a fresh session picking this up. Read this, then `AUDIO-PLAN.md` (the design record) and
`libagora-audio/README.md` (the component's own contract). This file is the *state*; those are the *reasons*.

## 1. Where everything is, and what is green

| repository | HEAD | pushed | state |
|---|---|---|---|
| `libagora-audio` (**new**) | `544d3f8` | yes, `origin/main` | clean; **12/12 tests, 0 warnings** on a clean configure |
| `libagora-app` | `44eee74` | yes, `origin/main` | clean; **215/215 tests** after `NSSound`/`NSBeep` |
| `release` | `66dba68` | **no — 2 commits ahead** | my `components.conf` line, plus one commit that was already pending |
| workspace (parent) | `6054ccc` | **no — 41 ahead** | `M libagora-audio`: the gitlink is one commit behind (`579f437` recorded, `544d3f8` actual) |

**First action for the next session:** `git -C ~/Development/Agora add libagora-audio` (and `release`, once you
push it) before the next parent commit. `git submodule status` must show no `-`.

`libagora-audio` is a submodule: `.gitmodules` entry, gitlink, `git submodule init` done, and
`release/components.conf` puts it **after `libagora-base`** — it resolves Foundation because 10.12's AUv3
headers import Foundation, which is Apple's layering rather than the tidier one. `libagora-app` links
`AgoraAudio::Audio` and `AppKit.h` exports `NSSound`.

## 2. The contract: macOS 10.12 is the specification

The API is **declaration-identical** to `MacOSX10.12.sdk`, not "inspired by" it:

- `tests/api/manifest-10.12.txt` is **generated** by `tools/api-manifest.py` from the reference headers and
  committed: **81 records, 1839 constants, 235 typedefs, 243 prototypes**. The SDK itself is never committed.
- Four gates keep it true: `api-layout` (`_Static_assert` on every size/alignment/offset from the manifest),
  `api-macros` (constant values and the flag macros by value), `api-prototypes` (every exported function
  through a pointer typed from the manifest — a drift is a compile error twice), `api-cxx` (the doors under
  `-std=c++17`).
- `tools/refshim/` is ~70 lines of ours (`TargetConditionals.h`, `Availability.h`, empty `MacTypes.h`, CF and
  dispatch *types only*, two `mach` stubs) so clang on Linux can parse Apple's headers. It is not installed.
- What identity does **not** cover: the include graph below our headers, and behaviour. Behaviour tests name
  the header sentence they check; there is no macOS here to diff against, and the README says so.

Regenerating the manifest (needs the SDK; `/tmp/refsdk` from the last session is gone after a reboot):

```sh
# stage a MacOSX10.12.sdk-like tree at /tmp/refsdk (System/Library/Frameworks/*.framework/Versions/A/Headers)
cd libagora-audio
python3 tools/api-manifest.py --sdk /tmp/refsdk --out tests/api/manifest-10.12.txt \
    CoreAudio/CoreAudioTypes.h CoreAudio/HostTime.h CoreAudio/AudioHardwareBase.h CoreAudio/AudioHardware.h \
    AudioToolbox/AudioFormat.h AudioToolbox/AudioConverter.h AudioToolbox/AudioFile.h \
    AudioToolbox/AudioFileStream.h AudioToolbox/ExtendedAudioFile.h AudioToolbox/AudioQueue.h \
    AudioToolbox/AudioServices.h AudioToolbox/AudioComponent.h AudioToolbox/AudioUnit.h \
    AudioToolbox/AudioOutputUnit.h AudioToolbox/AUGraph.h
```

Tip: the headers came from the `phracker/MacOSX-SDKs` raw tree (`MacOSX10.12.sdk/...`). Only the CoreAudio and
AudioToolbox frameworks have been staged so far; AudioUnit.framework's headers are flat inside AudioToolbox.

## 3. What exists, door by door

| door | implemented | refused, by name |
|---|---|---|
| `CoreAudio/CoreAudioTypes.h` | the structures, time stamps, flag vocabulary, status codes, `AudioChannelLayout`/`AudioBufferList` variable-length traps | the full constant tables (the manifest holds them; add with the phase that needs them) |
| `CoreAudio/HostTime.h` | `clock_gettime(CLOCK_MONOTONIC)` scaled to 1e9 ticks/s; conversions invert | — |
| `CoreAudio/AudioHardware*.h` | the object model: 5 property functions, listeners (proc **and** block, wildcards), io procs, the in-process mixer, volume/mute/clock; **two backends** (`null` always, ALSA when `pkg-config alsa`) | `kAudioDevicePropertyBufferFrameSize` writes, deprecated doors are *translated*, not refused |
| `AudioToolbox/AudioFormat.h` | `FormatInfo`, `NumberOfChannelsForLayout`, `ChannelLayoutForTag`, `ValidateChannelLayout` | every other selector (`'prop'`) |
| `AudioToolbox/AudioConverter.h` | both calling models, 14 properties, format + rate (windowed-sinc, 32 taps) | non-PCM (`'fmt?'`), `ConvertBuffer` across a rate change |
| `AudioToolbox/AudioFile.h` | **WAV, AIFF, CAF** read/write with size patching; byte and packet doors | compressed formats, unknown containers, FSRef doors (not declared, on purpose) |
| `AudioToolbox/ExtendedAudioFile.h` | open/create/wrap, read/write/write-async, seek/tell, client format (format **and** rate inside) | — |
| `AudioToolbox/AudioFileStream.h` | incremental parse of the same three containers, listener + packet callbacks | `AudioFileStreamSeek` (`'nope'`) |
| `AudioToolbox/AudioQueue.h` | output queues: buffers, refilling callback (lock released), volume as a **parameter**, properties | input queues, timelines, taps, offline render |
| `AudioToolbox/AudioServices.h` | system sounds by URL + the **generated** alert (1.5 kHz decay) | properties (`'pty?'`) |
| `AudioToolbox/AudioComponent.h` | a registry of **three** built-ins; find/count/describe/copy-name/instance | any fourth thing (no plug-in ABI) |
| `AudioToolbox/AudioUnit.h` | `DefaultOutput`, `AUConverter`, `MultiChannelMixer`; properties, parameters, `AudioUnitRender` | `AudioUnitProcess`, render notify, scheduled parameters |
| `AudioToolbox/AudioOutputUnit.h` | start/stop an output unit on the default device | — |
| `AudioToolbox/AUGraph.h` | nodes, connections, per-input callbacks, open/init/start/stop, cycle refusal | sub-graphs and the Carbon node doors (not declared) |

Measured, as of the last green run: 44.1 k → 48 k SNR **85.2 dB**; int16 round trip **bit-exact**; WAV/AIFF/CAF
round trips `memcmp`-exact; the null backend renders **12 000 frames in 250 ms** (±20% band); two io procs
0.25 + 0.125 mix to **0.375**; a queue, a unit and a graph each reach the device at the value they were given;
mute mixes **0.0**.

## 4. Build and test

```sh
C=/usr/bin/clang-19
cmake -S libagora-audio -B libagora-audio/build -DCMAKE_C_COMPILER=$C \
      -DCMAKE_CXX_COMPILER=/usr/bin/clang++-19 \
      -DCMAKE_PREFIX_PATH=$PWD/build-prefix -DCMAKE_INSTALL_PREFIX=$PWD/build-prefix
cmake --build libagora-audio/build -j"$(nproc)"
ctest --test-dir libagora-audio/build --output-on-failure     # 12 tests, ~2 s
```

Through the federation: `"$HOME/.agents/skills/agora-desktop/scripts/agora-build.sh" --only libagora-audio --test`
(this works now that `components.conf` lists it).

- `-DBUILD_TESTING=OFF` builds no test target at all (what the release driver passes).
- `-DAGORA_AUDIO_WITH_ALSA=OFF` drops the ALSA backend; the HAL falls back to the null device.
- The ALSA leg runs the same `hal` suite against ALSA's `null` PCM (`hal-alsa`); it skips only the pacing
  assertion, which is a fact about the plugin rather than about this library.
- Suites state their backend in code (`fn_agora_audio_set_driver`, `AudioToolbox_internal.h`), never from the
  environment, so a developer's `AGORA_AUDIO_DRIVER` cannot change what a test measured.

## 5. Traps already paid for — do not pay twice

1. **`snd_pcm_uframes_t` is `unsigned long`.** Handing ALSA the address of a `UInt32` field writes eight bytes
   into a four-byte slot: no compile error, then a glibc `malloc` assertion three frames later.
2. **A queue buffer that ends exactly on a quantum boundary** left every other device quantum silent when the
   render loop `break`s; it must hand the buffer back and keep filling.
3. **`AudioServicesPlaySystemSound` deadlocked** on its own non-recursive lock (caller held it, `fn_play`
   took it again). Callbacks and lock acquisition never nest.
4. **The graph's cycle check walked connections backwards**, found no ring, installed one, and the pull
   recursed until the stack ran out. Ask "does the destination already reach the source".
5. **AIFF's 80-bit sample rate**: `mantissa * 2^(exponent − 16383 − 63)`; wrong bias reads 48000 as 0.73 Hz.
6. **`__nonnull` is glibc's function attribute.** The reference parse rewrites Darwin's spelling in a scratch
   copy; our headers use `_Nonnull`/`_Nullable`.
7. **`CF_ENUM` in Core Foundation's C fallback form** (`_type _name; enum`) is what Apple compiles in C, and
   what makes `CF_ENUM(UInt32, X) {…}` usable here.
8. **Constants the manifest corrected** (all were "remembered" wrong first): `'acid'`/`'acod'` for the
   converter's stream descriptions; audio-file unsupported property is `'pty?'`; **no**
   `kAudioFilePropertyFileLengthFrames` in 10.12 (PCM packets are frames); **no**
   `kAudioUnitErr_InvalidPropertySize` (use `-10851`); `AudioChannelLayout` has
   `mNumberChannelDescriptions`; `AudioDeviceIOProcID` *is* `AudioDeviceIOProc`; `inInputTime` is not nullable.
9. **`libagora-app` is MRR, not ARC** (it uses `[super dealloc]`), its sources are globbed, and its two census
   ledgers must be edited **deliberately** when the AppKit surface changes: `tests/api-10.6-census.txt` (both the
   `sel:`/`proto:` lines and the summary counts) and `tests/refusal_census.txt` (per-file count and total).
10. **`LD_LIBRARY_PATH` order**: the installed prefix shadows a fresh build. Put the component's `build`
    directory first when checking a change, and `ldd` what actually loaded.

## 6. Next work, in the order the plan argues for

### (a) AUv3 — the rest of phase 5, and the only Objective-C in this component

`AudioToolbox/AUAudioUnit.h` and `AUParameters.h` **import Foundation**, so this is where the component stops
being C-only — which is why it already sits above `libagora-base`.

- `CMakeLists.txt`: `project(AgoraAudio LANGUAGES C OBJC)`, `find_package(Foundation CONFIG REQUIRED)`,
  `Foundation::Foundation` PUBLIC.
- Headers first, from the manifest (add both to the generator's header list), then:
  `AUAudioUnit` (a wrapper **over** the existing `AudioUnit` instance: `componentDescription`,
  `parameterTree`, `inputBusses`/`outputBusses`, `maximumFramesToRender`, `renderBlock`, `allocateRenderResources`
  / `deallocateRenderResources`, `startHardware`/`stopHardware`), `AUAudioUnitBus`/`AUAudioUnitBusArray`,
  `AUParameter`/`AUParameterGroup`/`AUParameterTree` (addresses, `value`, `setValue:originator:`,
  `implementorValueObserver`…).
- `kAudioUnitSubType_DefaultOutput` becomes reachable as an `AUAudioUnit` through the component registry, so
  `AudioComponentInstanceNew` keeps returning the C instance and the ObjC class wraps it — Apple's own split.
- App-extension headers (`AudioUnitExtension.h`, `AUAudioUnitFactory` as an extension) are **out of scope**;
  say so in the README rather than shipping a class that cannot be loaded.
- Gates: the existing `api-prototypes` covers C only; add an `api-objc` compile-only TU (or extend the ledger
  approach) for the class/protocol surface, and extend `api-layout` if any struct gains a `_Nullable` field.
- Test: an `AUAudioUnit` around the default-output unit, bus formats, a render block, a parameter tree round
  trip — headless, on the null backend, like `unit`.

### (b) PipeWire backend

The seam is already there: `agora_driver` in `AudioToolbox_internal.h` (describe devices, start, stop) and
`fn_agora_device_render`. A PipeWire driver describes the registry's devices, opens a stream in its process
callback and calls `fn_agora_device_render`. Add `-DAGORA_AUDIO_WITH_PIPEWIRE`, the `libpipewire-0.3` pkg-config
name (not `pipewire-0.3`), a `hal-pipewire` test leg against a live server, and `AGORA_AUDIO_DRIVER=pipewire`.
This machine has PipeWire 1.4.2 running with four playback devices, so it is measurable.

### (c) `libagora-app`'s remaining audio TODOs

- **A suite for `NSSound`** (it has none): `-duration`, `-isPlaying` after `-play`, `-loops` re-enqueue,
  `-stop`, `+soundNamed:`, `NSSoundDelegate`. Follow the census-edit rule in §5.9.
- `NSBundleAdditions.h` still owes its **header split**: `-pathForSoundResource:` belongs in `NSSound.h` now
  that the class exists (the file's own comment says so).
- `NSButtonCell.m` still excludes `_sound` from archiving "because this tier does not ship `NSSound`" — it can
  become an archived key.
- `COCOA-10.11-SURFACE-PLAN.md` A5: the `NSSound` row says "refused or adapted"; it is implemented now.

### (d) Smaller, in the plan's own order

- `sndio` backend for the BSDs (`AudioHardware-sndio.c`), labelled **written, not measured** until a BSD run —
  the `EventStream-kqueue.c` convention.
- `CoreMIDI` stays out of this component (a different device class, no consumer); a `libagora-midi` if one
  appears.
- `AudioQueue`'s input side, timelines, taps; `AUGraph` sub-graphs; the remaining `AudioFormat` selectors —
  each is a real door whose absence is currently declared and refused by name.

## 7. Open decisions

1. **AUv3 scope**: the parameter tree and buses, or also `AUAudioUnitFactory`/app-extension loading? (The plan
   says in-process only; recommend keeping that.)
2. **Volume on the device vs on the queue/unit**: both exist and multiply today. Apple's HAL volume is per
   device; this is consistent, but worth stating in the README when AUv3 lands.
3. **`AudioServices` one-queue reuse**: a second alert restarts the queue. If an app needs overlapping system
   sounds, that is the place to look.
4. **Where `AUDIO-PLAN.md` lives long-term**: it is committed at the workspace root; the component's README has
   taken over the current-state job, so the plan can be folded into the component once phase 5 closes.
