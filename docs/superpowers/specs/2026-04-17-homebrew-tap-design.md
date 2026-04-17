# Homebrew Tap Design

**Status:** Approved design — ready for implementation plan.

**Goal:** Create a Homebrew tap repo (`georgemandis/homebrew-tap`) with a formula for `whereami` so users can install via `brew install georgemandis/tap/whereami`.

**Scope:** This is sub-project 2 of the distribution pipeline. It consumes release artifacts produced by the GitHub Actions workflow (sub-project 1, complete). Scoop, Chocolatey, and .deb are separate sub-projects.

---

## Repo

New **public** GitHub repo: `georgemandis/homebrew-tap`.

Homebrew requires tap repos to be public. The naming convention `homebrew-tap` maps to the tap name `georgemandis/tap`, so users install with `brew install georgemandis/tap/whereami`.

---

## Files

### `Formula/whereami.rb`

A Ruby formula using Homebrew's DSL. Structure:

- **Metadata:** `desc`, `homepage`, `license` (MIT), `version` ("0.1.0").
- **Platform/architecture selection:** `on_macos` and `on_linux` blocks, each with `if Hardware::CPU.arm?` / `else` for architecture detection. Four combinations total:
  - macOS aarch64 → `whereami-v0.1.0-macos-aarch64.tar.gz`
  - macOS x86_64 → `whereami-v0.1.0-macos-x86_64.tar.gz`
  - Linux aarch64 → `whereami-v0.1.0-linux-aarch64.tar.gz`
  - Linux x86_64 → `whereami-v0.1.0-linux-x86_64.tar.gz`
- **URLs:** point to `https://github.com/georgemandis/whereami/releases/download/v0.1.0/<archive>`.
- **SHA256:** hardcoded per archive. Computed from the v0.1.0 release artifacts during implementation.

### Install method

**macOS:** The archive contains a `whereami.app` bundle (required for CoreLocation permissions) and a `whereami` symlink pointing into it. The formula installs the `.app` bundle to the prefix directory and creates a symlink in `bin/`:

```ruby
on_macos do
  # ... url/sha256 selection above ...
  def install
    prefix.install "whereami.app"
    bin.install_symlink prefix/"whereami.app/Contents/MacOS/whereami" => "whereami"
  end
end
```

**Linux:** The archive contains just the `whereami` binary. Straightforward:

```ruby
on_linux do
  # ... url/sha256 selection above ...
  def install
    bin.install "whereami"
  end
end
```

Note: the exact Ruby DSL structure for combining platform-specific URLs with a shared install method may need adjustment during implementation. Homebrew's `on_macos`/`on_linux` blocks can contain `url`/`sha256` declarations as well as install logic. The implementer should follow the Homebrew formula cookbook for the correct pattern.

### Test block

```ruby
test do
  assert_match "Usage: whereami", shell_output("#{bin}/whereami --help")
end
```

### `README.md`

Short file in the tap repo explaining what it is and how to install:

```
# homebrew-tap

Homebrew formulae for tools by George Mandis.

## Install

brew install georgemandis/tap/whereami
```

---

## Install experience

```bash
# One-liner (recommended)
brew install georgemandis/tap/whereami

# Or tap first, then install
brew tap georgemandis/tap
brew install whereami
```

---

## Update workflow (manual for v1)

When cutting a new `whereami` release:

1. Download all 4 Homebrew-relevant archives (macOS aarch64, macOS x86_64, Linux x86_64, Linux aarch64 — not Windows).
2. Compute SHA256 for each: `shasum -a 256 whereami-v*.tar.gz`
3. Update `Formula/whereami.rb` with the new version string, URLs, and checksums.
4. Commit and push to `homebrew-tap`.

This is ~5 minutes of work per release. Automation (e.g., a GitHub Action in the `whereami` repo that auto-updates the formula after a release) can be added later if release frequency justifies it.

---

## Explicitly out of scope

- **Windows:** Homebrew doesn't run on Windows.
- **Automated formula updates:** manual for v1 (YAGNI).
- **Cask format:** Casks are for GUI `.app` bundles installed to `/Applications`. Our `.app` bundle is a CLI permission wrapper, not a user-facing app. A formula is correct.
- **Submission to homebrew-core:** requires 75+ GitHub stars and formal review. A personal tap is the right starting point.
- **Build-from-source formula:** we distribute pre-built binaries. A source formula (with `depends_on "zig"`) could be added later but is not needed now.

---

## Success criteria

- `brew install georgemandis/tap/whereami` installs a working `whereami` binary on macOS (aarch64 and x86_64) and Linux (x86_64 and aarch64).
- On macOS, `whereami` resolves into the `.app` bundle so CoreLocation permissions work.
- On Linux, `whereami` is a standalone binary.
- `brew test whereami` passes (runs `whereami --help` and checks output).
- The formula specifies the correct SHA256 for each archive (verified during implementation by downloading and checksumming the v0.1.0 release artifacts).
