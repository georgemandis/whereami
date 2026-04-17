# .deb Packaging Design

**Status:** Approved design — ready for implementation plan.

**Goal:** Add `.deb` packaging to the existing Linux CI jobs so each release includes `whereami_<version>_amd64.deb` and `whereami_<version>_arm64.deb` as release artifacts.

**Scope:** This is the final sub-project of the distribution pipeline. It modifies the existing `build-linux` job in `release.yml` — no new repos, no new jobs, no external tooling.

---

## Approach

Add a "Package .deb" step to the existing `build-linux` job. The step creates a `.deb` directory structure and runs `dpkg-deb --build`. The resulting `.deb` is uploaded as an additional artifact alongside the existing `.tar.gz`.

No PPA, no apt repository, no signing. Users download the `.deb` from GitHub Releases and install with `sudo dpkg -i`.

---

## `.deb` contents

```
/usr/bin/whereami                          # the binary
/usr/share/applications/whereami.desktop   # GeoClue2 recognition
```

---

## Package metadata (`DEBIAN/control`)

```
Package: whereami
Version: <version from tag, e.g. 0.1.0>
Architecture: <amd64 or arm64>
Maintainer: George Mandis <george@mand.is>
Description: Get your current location from the command line using native OS APIs
Homepage: https://github.com/georgemandis/whereami
Depends: libdbus-1-3
Section: utils
Priority: optional
```

The `Architecture` field uses Debian naming: `amd64` (not `x86_64`) and `arm64` (not `aarch64`).

---

## CI changes

### Matrix update

The `build-linux` matrix currently has:

```yaml
include:
  - runner: ubuntu-latest
    archive_suffix: linux-x86_64
  - runner: ubuntu-24.04-arm
    archive_suffix: linux-aarch64
```

Add a `deb_arch` field to map to Debian architecture names:

```yaml
include:
  - runner: ubuntu-latest
    archive_suffix: linux-x86_64
    deb_arch: amd64
  - runner: ubuntu-24.04-arm
    archive_suffix: linux-aarch64
    deb_arch: arm64
```

### New step: "Package .deb"

Added after the existing "Package archive" step. Creates the directory structure, writes `DEBIAN/control`, copies the binary and `.desktop` file, runs `dpkg-deb --build`.

### Artifact upload

The existing `upload-artifact` step uploads the `.tar.gz`. A second `upload-artifact` step uploads the `.deb`. Both are uploaded as separate artifacts so the release job can collect them all.

---

## Naming convention

Standard Debian format: `whereami_<version>_<arch>.deb`

Examples:
- `whereami_0.1.0_amd64.deb`
- `whereami_0.1.0_arm64.deb`

When the build is from a non-tag push, version uses the `dev-<sha>` format to match the existing `.tar.gz` naming.

---

## Install experience

```bash
# Download from GitHub Releases
curl -LO https://github.com/georgemandis/whereami/releases/download/v0.1.0/whereami_0.1.0_amd64.deb

# Install
sudo dpkg -i whereami_0.1.0_amd64.deb
```

---

## Explicitly out of scope

- **PPA / apt repository:** YAGNI for now. Users download from GitHub Releases.
- **Signing the `.deb`:** not required for manual `dpkg -i` installs.
- **Post-install scripts:** not needed. The binary and `.desktop` file are sufficient.
- **Man pages:** not planned.
- **Uninstall hooks:** `dpkg -r whereami` handles removal automatically based on the file list.

---

## Success criteria

- Both `.deb` files (`amd64` and `arm64`) appear as release artifacts on GitHub Releases.
- `sudo dpkg -i whereami_<version>_<arch>.deb` installs `/usr/bin/whereami` and `/usr/share/applications/whereami.desktop`.
- `whereami --help` works after install.
- `dpkg -I whereami_<version>_<arch>.deb` shows correct metadata including `libdbus-1-3` dependency.
