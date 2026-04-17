# whereami CI + GitHub Releases Design

**Status:** Approved design — ready for implementation plan.

**Goal:** Set up GitHub Actions to verify builds on every push to `main` and produce versioned release artifacts on tag push, covering all 5 supported platform/architecture targets.

**Scope:** This is sub-project 1 of the distribution pipeline. It produces the artifacts that all downstream package managers (Homebrew, Scoop, Chocolatey, .deb) will consume. Those package managers are separate sub-projects with their own spec → plan → implement cycles.

---

## Trigger model

- **On push to `main`:** Build all 5 targets. Verify compilation succeeds. No artifacts uploaded to Releases — this is a CI check only.
- **On tag push matching `v*` (e.g., `v0.1.0`):** Build all 5 targets, create a GitHub Release with the tag name as the release title, attach all 5 archives.

---

## Runners and build matrix

Two GitHub Actions runners. Zig handles cross-compilation; the only platform-specific requirement is macOS `codesign`.

### macOS runner (`macos-latest`)

Targets:
- `aarch64-macos` (native)
- `x86_64-macos` (Zig cross-compile)

Build steps per target:
1. Clean `zig-out/` before each target build (both targets output to the same directory, so the second would overwrite the first if not archived in between).
2. `zig build bundle` — produces `zig-out/whereami.app` with ad-hoc signing (`codesign --force --sign -`).
3. Create a `whereami` symlink pointing to `whereami.app/Contents/MacOS/whereami`.
4. Package into a `.tar.gz` archive containing the `.app` bundle directory and the `whereami` symlink.

### Linux runner (`ubuntu-latest`)

Targets:
- `x86_64-linux` (native or Zig cross-compile — either works)
- `aarch64-linux` (Zig cross-compile)
- `x86_64-windows` (Zig cross-compile)

Build steps per target:
1. `zig build` — produces `zig-out/bin/whereami` (or `whereami.exe` for Windows).
2. Linux targets: package into `.tar.gz` containing the `whereami` binary.
3. Windows target: package into `.zip` containing `whereami.exe`.

The Linux runner does NOT need `libdbus-1-dev` installed for building — Zig links against `dbus-1` dynamically at runtime, not at build time. (If the Zig build system does require headers at compile time for the extern declarations, install `libdbus-1-dev` via `apt-get`.)

---

## Artifact naming

All archives include the version from the git tag:

```
whereami-v0.1.0-macos-aarch64.tar.gz
whereami-v0.1.0-macos-x86_64.tar.gz
whereami-v0.1.0-linux-x86_64.tar.gz
whereami-v0.1.0-linux-aarch64.tar.gz
whereami-v0.1.0-windows-x86_64.zip
```

The version string is extracted from the tag ref (e.g., `refs/tags/v0.1.0` → `v0.1.0`).

---

## Release creation

On tag push, after both runners complete successfully:

- A final job (or a step in one of the runners after artifacts are uploaded) creates a GitHub Release.
- Release title: the tag name (e.g., `v0.1.0`).
- Release notes: auto-generated from commits since the last tag. Can be hand-edited after creation.
- All 5 archives attached as release assets.
- Implementation can use either `gh release create` or a well-maintained action like `softprops/action-gh-release`. The plan should pick whichever is simpler.

---

## macOS archive contents (detail)

Each macOS `.tar.gz` contains:

```
whereami-v0.1.0-macos-aarch64/
├── whereami.app/
│   └── Contents/
│       ├── Info.plist
│       └── MacOS/
│           └── whereami
└── whereami -> whereami.app/Contents/MacOS/whereami
```

The symlink is what makes the tool behave like a normal CLI binary while still inheriting the `.app` bundle's location permissions from macOS. This mirrors the local `zig build bundle` behavior already in `build.zig`.

---

## Linux and Windows archive contents (detail)

Linux `.tar.gz`:
```
whereami-v0.1.0-linux-x86_64/
└── whereami
```

Windows `.zip`:
```
whereami-v0.1.0-windows-x86_64/
└── whereami.exe
```

---

## File location

Single workflow file: `.github/workflows/release.yml` in the main `whereami` repo.

---

## Explicitly out of scope

- Homebrew formula creation or auto-update (separate sub-project).
- Scoop manifest creation or auto-update (separate sub-project).
- Chocolatey package publishing (separate sub-project).
- `.deb` packaging (can be added as a later enhancement to this workflow or as its own sub-project).
- Real Apple Developer code signing (ad-hoc only, same as local builds).
- Automated changelog beyond GitHub's default auto-generated notes.
- Caching of Zig installation or build artifacts in CI (nice-to-have optimization, not required for v1).
- Running tests in CI (there are no automated tests in this project currently).

---

## Success criteria

- Pushing a commit to `main` triggers a workflow that builds all 5 targets and reports success/failure.
- Pushing a tag like `v0.1.0` triggers the same builds and then creates a GitHub Release with all 5 archives attached.
- Each archive can be downloaded, extracted, and the binary inside runs (verified manually on at least one platform after the first real release).
- The artifact naming convention matches the spec so downstream package-manager formulas can template URLs predictably.
- The macOS archives contain the `.app` bundle and the `whereami` symlink.
