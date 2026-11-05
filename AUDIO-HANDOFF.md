# AUDIO-HANDOFF — `libagora-audio`, state at the end of phases 3, 5, 6a and 7

For a fresh session picking this up. Read this, then `AUDIO-PLAN.md` (the design record) and
`libagora-audio/README.md` (the component's own contract). This file is the *state*; those are the *reasons*.

## 1. Where everything is, and what is green

| repository | HEAD | pushed | state |
|---|---|---|---|
| `libagora-audio` | see `git log -1` | yes, `origin/main` | clean; **17/17 tests** (16 run, `hal-sndio` skips), 0 warnings on a clean configure, and the same suite green with `-DAGORA_AUDIO_WITH_MPG123=OFF` (where `mp3` reports a skip) |
| `libagora-app` | `2b2a954` | yes, `origin/main` | clean; **216/216 tests**, including the new `appkit-nssound` |
| `release` | `66dba68` | yes, `origin/main` | `libagora-audio` is in `components.conf` above Foundation |
| workspace (parent) | see `git log -1` | yes | every component it pins is pushed, **except `viewer`** — that repository has no remote at all, so its pin is local-only and a fresh clone cannot resolve it |

**First action for the next session:** `git submodule status` and check that nothing shows `-` for a component
in `components.conf` (`libagora-webview` is uninitialised and is not in it). Then pick up `## 6` below.

`libagora-audio` is a submodule, sits **after `libagora-base`** in `release/components.conf`, and links
`Foundation::Foundation` **PUBLIC** — which is the same reason it sits there, and only makes it more true.
ALSA, PipeWire and sndio are **PRIVATE** links behind `AGORA_WITH_ALSA` / `AGORA_WITH_PIPEWIRE` /
`AGORA_WITH_SNDIO`, all `AUTO`; the MPEG audio decoder is a fourth, `AGORA_AUDIO_WITH_MPG123`, and it is the one
that changes what the library can *play* rather than only where it plays it.

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
| `CoreAudio/AudioHardware*.h` | the object model: 5 property functions, listeners (proc **and** block, wildcards), io procs, the in-process mixer, volume/mute/clock; **three backends** (`null` always, ALSA when `pkg-config alsa`, PipeWire when `libpipewire-0.3`) and sndio where libsndio is; **an input side** — a capture stream per device, the cycle's input handed to every io proc as `inInputData` (one buffer per cycle, read-only, because it is the microphone), and the null device **hears a ramp** so capture is testable with no hardware | `kAudioDevicePropertyBufferFrameSize` writes, deprecated doors are *translated*, not refused; the three real backends open **no** capture stream yet, so their devices describe `has_input = false` |
| `AudioToolbox/AudioFormat.h` | `FormatInfo`, `NumberOfChannelsForLayout`, `ChannelLayoutForTag`, `ValidateChannelLayout` | every other selector (`'prop'`) |
| `AudioToolbox/AudioConverter.h` | both calling models, 14 properties, format + rate (windowed-sinc, 32 taps) | non-PCM (`'fmt?'`), `ConvertBuffer` across a rate change |
| `AudioToolbox/AudioFile.h` | **WAV, AIFF, CAF** read/write with size patching; byte and packet doors; **MPEG-1/2/2.5 Layer III read** — a packet table walked from the stream's own sync words, ID3v2 skipped by its size field, and `kAudioFilePropertyPacketTableInfo` (`'pnfo'`) answering the encoder's gapless trim | writing MPEG (`kAudioFileUnsupportedFileTypeError`); every other compressed format and unknown container; `PacketToFrame`/`FrameToPacket` (not declared); FSRef doors (not declared, on purpose) |
| `AudioToolbox/ExtendedAudioFile.h` | open/create/wrap, read/write/write-async, seek/tell, client format; **decodes MPEG in front of the ordinary pipeline**, so the converter above it only ever sees linear PCM; a seek restarts the decoder at the frame that holds the sample asked for; **`FileLengthFrames` reports the trimmed length** when the file declares one | a compressed file in a build with no decoder is refused *at open*, by name |
| `AudioToolbox/AudioFileStream.h` | incremental parse of the same **four** containers, listener + packet callbacks; an MPEG stream reports every packet with its own description (a PCM stream's have none), skips an ID3v2 tag by its size, resynchronises a byte at a time, and reads the **Xing/Info tag** so its packet and byte counts are exact from the first frame | `AudioFileStreamSeek` for a stream with no table (`'nope'`) — PCM always, MPEG when the first frame is not the tag; the tag's gapless delay/padding is not applied |
| `AudioToolbox/AudioQueue.h` | **input and output** queues (a capture queue is the same object running backwards: empty buffers in, filled buffers back, the device's channels mapped to the client's, the converter facing the other way, the tap on the cycle's client-format audio), buffers, refilling callback (lock released), volume as a **parameter**, properties, **timelines** (a remembered time base that reports a start, a stop or a reset once), **offline render** (the queued buffers, in the client's format, into the caller's buffer — with the finished ones handed back through the same callback), mono↔stereo mapping, and **one processing tap** (`New`/`Dispose`/`GetSourceAudio`/`GetQueueTime`, the five flags, in-place processing, a **siphon**, the start/end-of-source flags, and a tap that runs on the offline path too) — the render path now **stages the source in the client's format** before converting it, which is what gives a tap something to process | a capture queue's volume (stored, not applied: a recording has no playback gain); real-backend capture (the `AudioQueue` and the HAL are ready, the drivers are not) |
| `AudioToolbox/AudioServices.h` | system sounds by URL + the **generated** alert (1.5 kHz decay); a pool of four queues so two alerts overlap, and completions that fire when the buffer comes back rather than when it was handed over | properties (`'pty?'`) |
| `AudioToolbox/AudioComponent.h` | a registry of **three** built-ins; find/count/describe/copy-name/instance | any fourth thing (no plug-in ABI) |
| `AudioToolbox/AudioUnit.h` | `DefaultOutput`, `AUConverter`, `MultiChannelMixer`; properties, parameters, `AudioUnitRender`; **`ParameterList`/`ParameterInfo`, `AudioUnitParameterInfo`, the unit and flag vocabulary** | `AudioUnitProcess`, render notify, scheduled parameters |
| `AudioToolbox/AudioOutputUnit.h` | start/stop an output unit on the default device | — |
| `AudioToolbox/AUGraph.h` | nodes, connections, per-input callbacks, open/init/start/stop, cycle refusal | sub-graphs and the Carbon node doors (not declared) |
| `AudioToolbox/AUParameters.h` **(new)** | `AUParameterNode`/`Group`/`Tree`/`Parameter`, the three observer blocks, the implementor observer/provider pair, the `(Factory)` creation doors | `NSSecureCoding` (not claimed); the group-template doors (not declared) |
| `AudioToolbox/AUAudioUnit.h` **(new)** | `AUAudioUnit` (+ `AUAudioInputOutputUnit` category), `AUAudioUnitBus`, `AUAudioUnitBusArray`, `AUAudioUnitPreset`, the block vocabulary, `-renderBlock`, `-parameterTree`, `-startHardware`/`-stopHardware`, `-allocateRenderResources` | out-of-process instantiation (answers with an error), MIDI, presets/state, `AUAudioUnitFactory` and app extensions (not declared) |

Measured, as of the last green run: the PipeWire leg of `hal` against this machine's server finds **3 sinks**,
puts the default first, and pulls **24 576 frames of a 0.5 tone in 512 ms**; 44.1 k → 48 k SNR **85.2 dB**; int16 round trip **bit-exact**; WAV/AIFF/CAF
round trips `memcmp`-exact; the null backend renders **12 000 frames in 250 ms** (±20% band); two io procs
0.25 + 0.125 mix to **0.375**; a queue, a unit and a graph each reach the device at the value they were given;
mute mixes **0.0**; through AUv3, two buses at volumes 1.0 and 0.25 mix **0.28125**, and a tree write lands in
`AudioUnitGetParameter`.

**Capture is measured against a source the suite can predict.** The null device's input is frame `n` = `(n % rate) /
rate` on the left and half that on the right, so: an input queue records **512-frame buffers** whose consecutive
frames step by exactly one ramp step (a dropped or duplicated frame is a step that is not), the right channel is the
left at half scale, a **mono** client measures **0.75** of the left (the two channels summed and halved — not 1.0,
which is one channel, and not 0.5, which is one of them), a tap on the recording halves that step and is refused
`kAudioQueueErr_InvalidTapType` for queue time, and a **draining stop** on a capture queue returns rather than waiting
for its own empty buffers. At the HAL, an io proc on the input device is handed the ramp as `inInputData` —
**13 calls of 512 frames** in 150 ms — and the input-scope stream reports `kAudioStreamPropertyDirection` = 1.

**The tap is measured at both ends**, because "the callback ran" and "the audio was processed" are different claims: the
tap is shown **0.500** and the device plays **0.250**; a **siphon** is shown 0.5 and the device still plays **0.5**; the
source flags report **StartOfStream** on the first pull and **EndOfStream** once the queue has run dry;
`GetQueueTime` answers the quantum's **512** frames of queue time; and `AudioQueueOfflineRender` goes through the tap
too, so a caller writing a file gets the processed audio.

**Phase 7 (`mp3` suite, 56 checks, two `ffmpeg` fixtures generated at configure time):** a 3 s 44.1 kHz stereo
MPEG-1 tone reports `1152` samples per frame, `0` bytes per packet, and **117 packets**; it decodes to **132 300
frames** of **132 300** — `ffmpeg`'s own number — at **440 Hz** by zero-crossing count, while the container's own
count is **134 784**, which is the encoder's padding; a 2 s 22.05 kHz mono MPEG-2 tone reports `576` per frame and
decodes to **44 100** frames at **330 Hz**; the same stream converted to **48 kHz float32** gives **143 982** frames
at **440 Hz**; a seek to 1.5 s puts the audio back at **442 Hz** (±0.5%) and a seek to zero re-decodes the first
4 096 frames **bit-exactly**; and `AudioFileCreateWithURL` for an MP3 and a 100-byte truncation of a valid frame
header are each refused **by name**. The incremental door is fed the same files a byte at a time, seven bytes at a time
and 4 096 bytes at a time, and **every packet it reports is compared with the file door's, byte for byte**: 117/117 and
80/80, the data offset at 44 (ffmpeg's own ID3v2 tag) and at 254 behind a synthetic 210-byte tag whose filler is
`0xFF`. The **Xing/Info tag** is asked of a stream fed only its first 4 KiB: it answers `AudioDataPacketCount` and
`AudioDataByteCount` exactly (117 and 73 350; 80 and 3 642), and `AudioFileStreamSeek` returns packet 0 at byte 44
exactly and the rest from the tag's hundredths within **130-260 bytes** of the file door's own offset (0.2-0.4% of the
audio), flagged `OffsetIsEstimated`. A stream entered mid-file — the first frame skipped, so no tag — answers
`ValueUnknown` and `'nope'`. The **gapless trim** is measured three ways: the reported length is **132 300** /
**44 100** — exactly the decoded frames — the table reads `valid 132 300 + priming 1 728 + remainder 756 = 134 784` and
`44 100 + 1 152 + 828 = 46 080`, which is what the packets hold, and the priming is the tag's frame plus the encoder's
own 576. **112 checks** in the build with the decoder, **72** without it (the container, the incremental door and the
tag need no decoder; the playback legs do).

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
ctest --test-dir libagora-audio/build --output-on-failure     # 17 tests, ~4 s
```

Through the federation: `"$HOME/.agents/skills/agora-desktop/scripts/agora-build.sh" --only libagora-audio --test`
(both scripts already pass `-DCMAKE_OBJC_COMPILER`).

- `-DBUILD_TESTING=OFF` builds no test target at all (what the release driver passes).
- `-DAGORA_AUDIO_WITH_ALSA=OFF` / `-DAGORA_AUDIO_WITH_PIPEWIRE=OFF` drop a backend (both default to `AUTO`); the
  HAL falls back to the null device.
- `-DAGORA_AUDIO_WITH_MPG123=OFF` drops the decoder. The container still reads — `AudioFile` walks frames without
  mpg123 — and `ExtAudioFileOpenURL` refuses the file at open with `kAudioFileUnsupportedDataFormatError`, which is
  what the `mp3` suite reports as a skip. **Check both configurations when touching the file doors**: this one is
  green today because it was tried, not because it is obvious.
- **With no `AGORA_AUDIO_DRIVER`, a client gets PipeWire if its server answers and `null` if not** — so on this
  desktop a beep is audible and in a container it is silent, without a variable being set. ALSA is *not* in that
  chain (see §7.1).
- The ALSA leg runs the same `hal` suite against ALSA's `null` PCM (`hal-alsa`); it skips only the pacing
  assertion. The PipeWire leg (`hal-pipewire`) runs it against the live server, skips pacing *and* the numbers
  the server chooses (rate, quantum, channel count), and **exits 77 = SKIP** when no server is reachable.
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
15. **PipeWire has no `pw_thread_loop_roundtrip`** in 1.4's headers, only `pw_core_sync` + the core's `done`
    event. The barrier is: hold the loop lock, `sync_seq = pw_core_sync(core, PW_ID_CORE, 0)`, then
    `pw_thread_loop_wait` until the `done` handler clears it. `pw_thread_loop_wait` **needs the lock held** and
    returns with it held; events are delivered with it held, which is what makes the signal safe.
16. **A `struct spa_hook` must outlive the object it is added to**, so it cannot be a compound literal at the
    `add_listener` call site. It lives in the engine/global struct.
17. **The registry is asynchronous and `AudioObjectGetPropertyData` is not.** Connect once, two round trips, then
    **remove both listeners** (`spa_hook_remove`, safe on a zeroed hook) so the device table cannot grow while a
    client is reading it. A sink that appears later is invisible until the process restarts — a documented
    limitation, not an event loop.
18. **`default.audio.sink` is JSON** (`{"name":"…"}`) and `spa_json` is a cursor: reading a key without
    consuming its value desynchronises every pair after it. Read key, then `spa_json_next`, then parse.
19. **`AudioConverterNew` will not change a channel count, and that is correct.** The queue is where mono→stereo
    belongs (`AudioQueue.c`'s `map_channels`), not the converter: teaching the converter to accept it would make
    it disagree with Apple and with its own `kAudioConverterChannelMap` door.
20. **A struct with an interior pointer cannot be returned by value.** The `auv3` suite's `fn_storage` fills
    a `render_storage` **in place**; returning one would leave `mBuffers[0].mData` pointing at the samples of
    a dead stack frame, and the render would write to nothing while the test read zeros.
21. **`mpg123_read` reports a message and the samples in the same call.** `MPG123_NEED_MORE` (-10) arrived with
    **290 492 bytes** of decoded audio in the same call; a decoder that branched on the status before taking
    `done` played 12 288 frames of a three-second file and dropped the rest. **Take the samples first, then read
    the code.** `MPG123_OUTBLOCK` is a suggestion, not a bound, so the buffer is sized from the caller's own room.
22. **There is no way to flush a feed-mode mpg123 handle.** `mpg123_feed(m, NULL, 0)` returns `0` and does
    nothing, and feeding a 128-byte ID3v1 `TAG` block does nothing either (measured on 1.32.10). The last frames
    appear only as the remaining bytes are fed and read, so "flush at end of file" is not a step — do not add one.
    The consequence is that **the end of the container is not the end of the audio**, and the read loop must stop
    on an *empty* refill rather than on `eof`.
23. **`ExtAudioFileSeek` never set `file_position` and nothing set `input_packet`.** The first made a seek a lie
    (the position came back, the audio did not move); the second made `fn_refill`'s PCM branch re-read from
    packet 0 on every refill, which is an infinite loop for any PCM file whose client format differs from the
    file's — the shape a rate change takes. Both fixed in phase 7; the refill now derives its start from
    `file_position`, which is the only thing that tracks it.
24. **`kAudioFileMP3Type` is `'MPG3'`, not `'mp3 '`.** 10.12 spells the three MPEG containers `'MPG1'`, `'MPG2'`,
    `'MPG3'`; the obvious-looking constant compiles, does not match the manifest's value, and `api-macros` fails.
    This is exactly the class of mistake the manifest exists for, and it caught one during phase 7.
25. **libmpg123 is not in `/usr/include` on Debian** (it is under `/usr/include/x86_64-linux-gnu/`), so
    `pkg-config --cflags libmpg123` is mandatory rather than decoration.
26. **A validator that requires its output pointer silently becomes a one-byte dropper.** `fn_mpeg_frame_header`
    first refused `out == NULL`; the stream's resynchroniser asks only "does a frame start here", so every such call
    answered no and the emitter ate the buffer one byte at a time — a file that decoded perfectly through the file door
    reported **zero** packets through the stream door. A predicate takes a NULL out, and `tests/mp3.c` feeds a fixture
    one byte at a time for exactly this class of bug.
27. **"I need more bytes yet" is not an error from `AudioFileStreamParseBytes`.** It returned
    `kAudioFileStreamError_DataUnavailable` until the first four bytes had arrived, which is right for a property and
    wrong for a parser: every caller feeding a socket breaks out of its loop on a non-zero status, so a stream
    delivered one byte at a time stopped at the first call. `0` and a buffered byte is the honest answer.
28. **MPEG's protection bit is inverted.** Bit 0 of the second header byte is **zero** when a CRC is present; every
    other flag a reader has met means the opposite. It matters here because a CRC moves the Xing tag two bytes, so a
    wrong reading is not a crash: the tag is simply not found and the stream reports "no length declared" for a file
    that declares one. Measured on both fixtures — `0xFF 0xFB` is unprotected, and the tag is at byte 36 of a 192 kbit/s
    44.1 kHz stereo frame.
29. **The Xing frame count excludes the frame that carries the tag, and its byte count includes it.** The tag says 116
    frames and 73 350 bytes for a file this door reports as 117 packets of 73 350 bytes: the tag's own frame is a packet
    here, so `packets = tag.frames + 1` and `bytes = tag.bytes` unchanged. Getting either wrong is a duration off by
    26 ms and a count off by one, which is exactly the kind of thing a viewer shows and nobody can explain.
30. **A TOC entry is a hundredth of the file, not a packet index.** `toc[i]` is `i`-percent of the *audio's bytes*, so a
    packet offset is an interpolation (`packet x 100 / packets`), and the answer is an estimate — 130-260 bytes out on
    this machine's fixtures. Packet 0 is exact because it is where the audio starts, and saying so is better than
    estimating a position the door already knows.
31. **The packet-table selector is `'pnfo'`, not `'pkin'`.** The third constant the manifest caught in this component
    (after `'MPG3'` and the converter's `'acid'`/`'acod'`). A wrong selector does not fail: the door answers
    `kAudioFileUnsupportedPropertyError` and a client silently shows the untrimmed length.
32. **The tag's own frame is priming, and the LAME block starts after the quality field.** The gapless arithmetic is
    `packets x samples = valid + priming + remainder` with priming = one frame + the encoder's delay: LAME's own
    "delay" alone under-counts by 1 152 samples per file, which is 26 ms of a seek bar that nobody can explain. And
    the extension block sits after the *quality* field (flag 8), so skipping that flag's four bytes reads the delay
    and padding one field early — measured: 576 delay + 756 padding on the 3 s fixture, not the values at the
    wrong offset.
33. **A block that outlives its frame needs `Block.h`, and a C file does not get it for free.** `AudioServices.c` is C;
    the compiler knows `^{}` syntax with `-fblocks` but declares no `Block_copy`/`Block_release`, so a stored completion
    block compiles into an implicit declaration and fails at link. The header comes from the runtime's include
    directory, which the target already has because the ObjC doors need it.
34. **A `ffmpeg`-generated fixture keeps its own padding apart from the decoder's.** The container counts padded
    frames; libmpg123 applies the LAME tag's gapless declaration, so the decoded count is the *audio's* length.
    Asserting "decoded == packets x samples-per-frame" fails by 2.5 frames on a 3 s file and by 3.4 on a 2 s VBR
    one. Assert the decoded count against the tone's duration and the packet count against it ±5 frames.
35. **A tap's output buffer is allocated by the call that produces it, so nothing may read it first.**
    `base = queue->tapped; available = fn_tap_process(...)` read the pointer *before* the call that reallocs it, and the
    first render of every tapped queue converted from `NULL`. The order of two statements was the whole bug, and a
    device thread rather than the caller found it. A function that produces a buffer should answer with the buffer.
36. **A siphon produces nothing, so its output is its source.** Handing a siphon the `tapped` buffer (which it never
    fills, and which does not exist on the first call) segfaulted; `fn_tap_process` now answers with a pointer — the
    tap's own buffer for a processing tap, the stage it was shown for a siphon — plus the frame count.
37. **A draining stop on a capture queue waits for ever.** `AudioQueueStop(queue, false)` waits until `current` is NULL
    and `pending_count` is 0 — which is *playback*'s definition of drained. A recording queue's pending list holds the
    caller's **empty** buffers, so it never empties: the stop would hang, and a test that called it would be a
    deadlock rather than a failure. Capture skips the wait.
38. **The cycle's input belongs to the device, not to the client.** One capture buffer is taken per cycle and handed
    to every io proc unchanged, read-only. Copying it per proc would have been the easy way to keep `inInputData`'s
    `const` honest and would also have made each proc see a *different* microphone — two clients on one device must
    see the same input, which is what a device's input is.
39. **A synthetic source is worth choosing for what it measures, not for what it sounds like.** The null device's input
    is a ramp, not a tone, because the question a capture test asks is "are these the frames, in this order, without a
    gap" — one subtraction per frame answers it, and a tone would have needed a pitch estimate to say less. The two
    channels differ by a factor of two for the same reason: it makes the channel map measurable (a summing client
    must measure 0.75, not 1.0, which is a fan-out, and not 0.5, which is one channel copied).
40. **The library's own suite was green because of an optimisation level.** `tests/converter.c` put two planes in a
    bare `AudioBufferList`, whose declared single element is not enough; the second write landed on the next stack
    word and turned a 64-frame split conversion into a one-frame one — **in a Debug build only**, because in Release
    `wanted` happened to sit somewhere the overrun did not reach. `AudioBufferList` is variable-length and the trap is
    in §3 of the README for exactly this reason; the fixture now carries its own storage. A suite that has only ever
    been run at `-O2` has not been run.

## 6. Next work, in the order the plan argues for

### (a) `libagora-app` — **done**, and what it found

The four `NSSound` items are closed in `libagora-app` (`tests/nssound.m`, `NSSound.h`, `NSButtonCell.m`, the A5
row). Three defects came out of the suite, and one of them was **this library's**:

1. **A queue could not play a mono file at all.** `AudioConverterNew` refuses a channel-count change (Apple does
   too — that is a channel map's job), so `AudioQueueNewOutput` for 16-bit mono 8 kHz failed at creation on a
   stereo device and every mono beep was silent. `AudioQueue.c` now converts to the *client's* channel count and
   fans out / sums down on the way into the device buffer (`map_channels`, `convert_format`, `map_scratch`), and
   `queue`'s suite measures a mono buffer at 0.5 on the stereo device. **A second channel mapping belongs here
   when one is wanted: `N`→`M` for `N, M > 1` is refused by name rather than approximated.**
2. `NSSound`'s second `-play` after a sound *finished* played silence: the queue hands a non-looping buffer back,
   so `_buffer != NULL` never meant "queued" (`_inFlight` now says so).
3. `+soundNamed:` returned the file's name rather than the name asked for.

### (a2) Phase 7, MPEG Layer III — **done**, and what it cost

`libagora-audio` reads MPEG-1, MPEG-2 and MPEG-2.5 Layer III through `AudioFile` and plays it through
`ExtAudioFile`, with `libmpg123` as a PRIVATE system dependency. Four things were worth the day they took:

1. **The container is a walk, not a header.** There is no length field, so `fn_mp3_parse` indexes every frame's
   offset and size once at open (ID3v2 skipped by its own size and the footer flag) and every later read is an
   index into that table. A VBR file's duration is therefore exact. The walk rejects a frame whose version/rate/
   channels disagree with the first one, because tag data contains accidental sync words.
2. **The decoder is not the converter.** MPEG is decoded *behind* `ExtAudioFile`'s staging buffer, so
   `AudioConverter` still refuses MPEG input (its suite asserts it) and the two facts stop looking like a
   contradiction.
3. **The fast path was the bug.** `ExtAudioFileRead` had a "the file's bytes are the client's frames" shortcut
   for the no-converter case; with a decoder it handed compressed bytes to a client asking for PCM. The condition
   is now `converter == NULL && decoder == NULL`, and the decoded case copies out of the staging buffer.
4. **`ExtAudioFileSeek` had never worked.** It returned the new position and moved nothing. It now sets
   `file_position` (with the rate ratio), restarts the decoder at the frame holding the requested sample, and
   drops the samples before it inside that frame. A seek to zero is bit-exact; a seek into the middle is
   frame-accurate, because the encoder's delay lives only in the first frame.

**The incremental door came after it, and it was the cheap part.** `fn_mp3_frame_at` became `fn_mpeg_frame_header` in
a file of its own (`AudioMpeg.c`), because two doors now walk the same four-byte header and a second copy of the bitrate
tables is exactly the drift the manifest exists to prevent. What the stream door needed was a state machine, not a
parser: skip the tag by its size, resynchronise a byte at a time, and buffer the frame that straddles a call boundary.
`fn_emit` still holds the PCM path, unchanged and unaware of either.

**The Xing/Info tag came third, and it is where a stream finally knows its own length.** It sits after the
side-information block — 32 bytes for MPEG-1 stereo, 17 for MPEG-1 mono, 17 for MPEG-2 stereo, 9 for MPEG-2 mono, plus
two for a CRC — and it holds a frame count, a byte count and a hundred-entry seek table. Two counts, one flag each, and
the seek table is what makes `AudioFileStreamSeek` answerable at all.

**Next for this phase:** nothing in the parse itself. What is left is a *policy* question that now has its data: the tag
also declares the encoder's delay and padding, so **the duration the file door reports could be the audio's true length
rather than the container's** (§7.6). That is a change to `AudioFile` and `ExtAudioFile`, not to the stream, and it wants
a test that compares a decoded frame count with a reported one. `AudioConverter`'s own MPEG support is *not* next: it is
refused on purpose (a decoder is a stream, a converter is a ring), and that decision is now measured in two places.

### (b) Smaller, in the plan's own order

- ~~`sndio` backend for the BSDs~~ — **written, compiled here, and not measured here** (`AudioHardware-sndio.c`,
  done). This machine has `libsndio-dev` 1.10.0, so the file is built and linked against the real header and the
  `hal-sndio` leg runs and **skips (77)** with no `sndiod` listening. What would lift the label is a BSD run — or
  any machine with a server — measuring four things this tree cannot: the sample format the server grants
  (`sio_getpar` after `sio_setpar`; anything but 32-bit signed native-endian is refused rather than played as
  noise), the buffer/round it paces with, `sio_write`'s blocking back-pressure, and `sio_eof` on a server that
  goes away. sndio has no float format, so the driver converts the mixer's float32 to 32-bit signed in its own
  thread — the only backend that has to.
- `CoreMIDI` stays out of this component; a `libagora-midi` if one appears.
- ~~`AudioQueue`'s timelines~~ — **done**: a timeline reports a start, a stop or a reset once, and
  `AudioQueueGetCurrentTime` compares its remembered time base against the queue's.
- ~~`AudioQueue`'s input side~~ — **done**, and the estimate was right about the shape: an input *device* (a scope in
  the HAL — already there, unused), a capture path in at least one backend, and a synthetic source in `null` to test it.
  What it cost:
  1. **The seam takes the cycle's input, not a per-client one** (§5.38): `fn_agora_device_render(id, capture, mix,
     frames)`, and `capture` is what every io proc is handed as `inInputData`.
  2. **The null device hears a ramp** (§5.39), which is what makes the whole thing measurable headlessly and is now
     the fixture every capture assertion is written against.
  3. **A capture queue is the same object backwards**, so it reuses the device, the converter, the stage, the channel
     map and the tap; what changes is the direction of each. The converter faces `(device → client)`, and the tap runs
     on the cycle's client-format audio *before* the caller's buffer — which is also what makes
     `kAudioQueueErr_InvalidTapType` reachable at last.
  4. **A drain on a capture queue is not a wait** (§5.37).
  What is left is the part that needs a real device: `snd_pcm_open(SND_PCM_STREAM_CAPTURE)`, a `PW_DIRECTION_INPUT`
  stream and `sio_open(SIO_REC)` in the three drivers, each of which only has to fill the buffer the seam already
  takes.
- ~~Processing taps~~ — **done**, and the prediction in the last handoff was right about where the work was: the
  obstacle was the render path, not the doors. What it cost:
  1. **The source is staged before it is converted.** `fn_stage_pull` gathers the enqueued buffers into a short FIFO in
     the client's own format, `fn_tap_process` runs on that, and the converter, the channel map and the volume are the
     tail. That is also why a tap's processing format is the *client's* format rather than the device's — which is
     what Apple promises and what `outProcessingFormat` could not honestly have answered before.
  2. **`GetSourceAudio` is what consumes the source.** Only what a tap pulls through it advances `stage_offset`, so
     what the tap did not take stays staged for the next quantum; a siphon takes the whole chunk without a copy and
     without being able to change it, which is what the flag means.
  3. **The tap answers with a pointer, not a count** (§5.35, §5.36), and it is asked for the quantum in *client* frames
     (`fn_stage_quantum`), while the stage is sized with two frames of margin for the resampler's window — the margin is
     what keeps an upsampling queue from a gap of silence at every quantum boundary.
  4. **`PreEffects` and `PostEffects` differ only in the flag here.** This queue has no effects between them, so both
     hear the source before the conversion and the volume. Said in the header and the README rather than papered over
     with two copies of the same call.
  5. **`AudioQueueOfflineRender` goes through the same chain**, because a tap does not know which path called it; the
     offline path is a stage and a copy, since its format is already the client's.
  What is left on this door is only what needs a *device*: taps on an input queue (`kAudioQueueErr_InvalidTapType` is
  unreachable while no backend opens a capture stream), and the effects `PostEffects` would sit after.
- `AudioQueueOfflineRender`'s *format* half (`AudioQueueSetOfflineRenderFormat` is not declared,
  so offline output is the client's format, which is what a file wants); `AUGraph` **sub-graphs** (their Carbon doors — `AUGraphNewNodeSubGraph`,
  `AUGraphGetNodeInfoSubGraph` — are not declared here, and declaring a door this tree cannot implement is what
  Tier B exists for); `kAudioFormatProperty_FormatList` (the constant is in the manifest, but its *specifier* is a
  calling convention the manifest does not record, so the door stays refused rather than guessed).
- AUv3's remaining optional doors, each a real question rather than a stub: `-fullState`/`-factoryPresets`
  need a state serialisation the C side does not have; MIDI needs a device class this component does not
  ship. Both are nil today and said so in the README.

## 7. Open decisions

1. ~~**Which backend is chosen with no `AGORA_AUDIO_DRIVER`.**~~ **Settled:** PipeWire → sndio → **ALSA** → `null`.
   The reason ALSA could not be in the chain was that it described a card whether or not one existed; its
   `device_count` is now a real `snd_pcm_open`/`close`, so the chain's condition is the same as the other two
   backends'. MEASURED with `XDG_RUNTIME_DIR` pointing at an empty directory: PipeWire declines, the ALSA probe
   reports no device on this machine, and the library falls back to `null` — no error, no silence mistaken for a
   failure.
2. **`AUAudioUnitBus.format` vs `AVAudioFormat`.** Settled the only way it can be without AVFoundation: a bus
   carries an `AudioStreamBasicDescription`. If `libagora-avfoundation` ever appears, this is the header to
   revisit — and the `auv3` suite is where the change will show.
3. **Volume on the device vs on the queue/unit**: both exist and multiply today. Apple's HAL volume is per
   device; this is consistent, but worth stating in the README when the next audio door lands.
4. ~~**`AudioServices` one-queue reuse**: a second alert restarts the queue.~~ **Settled:** a pool of four queues, so
   overlapping alerts both play; a fifth interrupts the oldest, which is what a buzzer does. The completion block
   now fires when the queue hands the buffer back, which is the moment the sound has been heard.
5. **Where `AUDIO-PLAN.md` lives long-term**: it is committed at the workspace root; the component's README has
   taken over the current-state job. Phase 5 is closed now, so the plan can be folded into the component.
6. ~~**What a compressed file's duration means, and whether to trim it.**~~ **Settled.** The file door answers
   `kAudioFilePropertyPacketTableInfo` (`'pnfo'` — not `'pkin'`) with the encoder's own numbers, and
   `ExtAudioFile`'s `FileLengthFrames` reports `mNumberValidFrames`. The container's count is still what
   `AudioDataPacketCount` answers, because every packet can be read whether or not it is audio; the two numbers
   differ by the trim, and both are reported. A file that declares nothing keeps the untrimmed length: the trim is
   the encoder's claim, and this door does not invent one.
7. **A second channel mapping.** The queue's `map_channels` handles mono<->stereo because that is a beep's shape, and
   it is where a wider map belongs — but `N`->`M` for `N, M > 1` cannot be computed from an `AudioStreamBasicDescription`
   alone: the queue's API carries no channel layout, so nothing says which source channel becomes which. The map that
   needed no layout is the one implemented; the rest waits for a door that describes one.
