# Scoop Bucket Design

**Status:** Approved design — ready for implementation plan.

**Goal:** Create a Scoop bucket repo (`georgemandis/scoop-bucket`) with a manifest for `whereami` so Windows users can install via `scoop install bucket/whereami`.

**Scope:** This is sub-project 3 of the distribution pipeline. It consumes the Windows x86_64 `.zip` from GitHub Releases (sub-project 1, complete). Homebrew tap (sub-project 2) is also complete. Chocolatey and .deb are separate sub-projects.

---

## Repo

New **public** GitHub repo: `georgemandis/scoop-bucket`.

Users install with:

```powershell
scoop bucket add bucket https://github.com/georgemandis/scoop-bucket
scoop install bucket/whereami
```

---

## Files

### `whereami.json`

Scoop manifest at repo root. Structure:

```json
{
    "version": "0.1.0",
    "description": "Get your current location from the command line using native OS APIs",
    "homepage": "https://github.com/georgemandis/whereami",
    "license": "MIT",
    "architecture": {
        "64bit": {
            "url": "https://github.com/georgemandis/whereami/releases/download/v0.1.0/whereami-v0.1.0-windows-x86_64.zip",
            "hash": "2373f16975b1cbca306d2778f0d44fd354e268957e931c16a81da6ef59d15bd5"
        }
    },
    "bin": "whereami.exe",
    "checkver": "github",
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/georgemandis/whereami/releases/download/v$version/whereami-v$version-windows-x86_64.zip"
            }
        }
    }
}
```

Key details:
- **`architecture.64bit` only** — we only build Windows x86_64 today.
- **`bin`** points to `whereami.exe`. Scoop auto-strips the zip's single top-level directory (`whereami-v0.1.0-windows-x86_64/`), so the `.exe` is directly accessible.
- **`checkver: "github"`** — lets Scoop detect new versions from GitHub releases (informational; does not auto-update hashes).
- **`autoupdate`** — defines the URL pattern so `scoop checkup` can report when an update is available, but the hash still needs manual updating.

### `README.md`

Short file in the bucket repo:

```
# scoop-bucket

Scoop bucket for tools by George Mandis.

## Install

scoop bucket add bucket https://github.com/georgemandis/scoop-bucket
scoop install bucket/whereami
```

---

## Install experience

```powershell
# Add the bucket (one time)
scoop bucket add bucket https://github.com/georgemandis/scoop-bucket

# Install
scoop install bucket/whereami
```

---

## Update workflow (manual for v1)

When cutting a new `whereami` release:

1. Download the Windows archive: `whereami-v<version>-windows-x86_64.zip`.
2. Compute SHA256: `certutil -hashfile whereami-v<version>-windows-x86_64.zip SHA256` (Windows) or `shasum -a 256` (macOS/Linux).
3. Update `whereami.json` with the new version string, URL, and hash.
4. Commit and push to `scoop-bucket`.

---

## Explicitly out of scope

- **ARM64 Windows:** no release artifact for it today.
- **Automated hash updates:** manual for v1 (YAGNI).
- **Submission to the main Scoop bucket:** requires community review and sufficient usage.
- **32-bit Windows:** not supported.

---

## Success criteria

- `scoop bucket add bucket https://github.com/georgemandis/scoop-bucket` succeeds.
- `scoop install bucket/whereami` installs a working `whereami.exe`.
- `whereami --help` outputs usage text.
