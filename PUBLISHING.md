# Publishing the Agora repositories

The workspace is a federation: this repository (`Agora`) holds one submodule per component, and the
`release` repository holds the same components again, pinned by tag. Publishing therefore means
pushing **every repository**, components first, so that every submodule pointer resolves.

Everything below assumes the GitHub CLI (`gh`) is authenticated for the `AgoraDesktop` organisation.

## What exists on the org already

```
AgoraDesktop/Agora              this workspace (private)
AgoraDesktop/release            the release pins and image build (private)
AgoraDesktop/libagora-core      Core Foundation
AgoraDesktop/libagora-dispatch  libdispatch + blocks runtime
AgoraDesktop/libagora-lcms2     little CMS
AgoraDesktop/libagora-objc      GNUstep libobjc2
AgoraDesktop/libagora-base      Foundation
AgoraDesktop/libagora-app       Application Kit
AgoraDesktop/libagora-text      Core Text
AgoraDesktop/libagora-drawing   Core Graphics
AgoraDesktop/libagora-watch     the change stream
AgoraDesktop/libagora-iconservices  Icon Services
AgoraDesktop/libagora-launchservices Launch Services
AgoraDesktop/window-server      the Wayland compositor
AgoraDesktop/widget-zoo         demonstration application
AgoraDesktop/workspace          Workspace — the desktop surface and file manager
AgoraDesktop/swift-toolchain    the Swift-on-Agora toolchain
AgoraDesktop/swift-interop-probe the Swift/Agora interop probes
AgoraDesktop/AgoraDesktop.github.io  project website (public)
AgoraDesktop/.github            org profile (public)
```

`workspace`, `swift-toolchain` and `swift-interop-probe` were created for this preparation and are
**public**; the component repositories above them are private. Flip the three with
`gh repo edit AgoraDesktop/<name> --visibility private` if the federation should be uniformly private.

## Push order

1. **Components with unpushed commits**, in any order (each is self-contained):

   ```sh
   for r in libagora-core libagora-drawing libagora-launchservices libagora-text \
            libagora-objc libagora-base libagora-app window-server; do
     git -C "$r" push -u origin main
   done
   ```

   `libagora-core`, `libagora-drawing`, `libagora-launchservices` and `libagora-text` also carry
   commits that were made before this preparation round; the push is the same.

2. **The new repositories:**

   ```sh
   for r in workspace swift-toolchain swift-interop-probe; do
     git -C "$r" push -u origin main
   done
   ```

3. **The release repository.** Its pins are already advanced to the component commits from step 1
   (and `workspace` is already a member), so it only has to be pushed:

   ```sh
   git -C release push -u origin main
   ```

4. **The workspace** (this repository) last, so that every pointer it records exists upstream:

   ```sh
   git push -u origin main
   ```

5. **A release tag**, when the image build is green:

   ```sh
   git -C release tag -a v0.1.0 -m "Agora 0.1.0"
   git -C release push origin v0.1.0
   ```

## Verifying the result

A fresh clone must resolve every submodule:

```sh
git clone --recursive https://github.com/AgoraDesktop/Agora.git agora-check
cd agora-check
git submodule status          # no leading '-' (uninitialised) or '+' (wrong revision)
```

Then build bottom-up (`libagora-dispatch`, `libagora-core`, `libagora-objc`, `libagora-base`, the
rest) into a shared prefix, and run `demo/agora-demo.sh` — it needs `window-server`, `workspace` and
`libagora-app` built. The Swift toolchain has its own gate: `swift-toolchain/scripts/verify-swift-port.sh`.

## Before the first push

- **Licence:** the root `LICENSE` is MIT (matching every component). Components that ship third-party
  code keep their upstream notices (`libagora-dispatch`, `libagora-lcms2`, `libagora-objc`,
  widget-zoo's fixtures); `release/debian/copyright` records the distribution view.
- **Secrets:** no credentials or private keys are tracked. Build output (`build/`, `build-prefix/`),
  the supplied Greybird theme and agent state (`.reasonix/`) are ignored.
- **Author identity:** the commits are by the project author; `git config user.name`/`user.email` are
  set per repository.
- **Submodule pointers:** `git submodule status` must print no `+` (the recorded revision differs
  from the checked-out one) before the workspace push.
