# CI + GitHub Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a GitHub Actions workflow that verifies builds on push to `main` and produces versioned release artifacts on tag push for all 5 supported targets.

**Architecture:** Single workflow file with two jobs (macOS and Linux runners). The macOS job builds both macOS architectures with `.app` bundles and codesigning. The Linux job cross-compiles Linux (two arches) and Windows targets. On tag push, a third job creates a GitHub Release and attaches all artifacts.

**Tech Stack:** GitHub Actions, Zig 0.15.2, `tar`/`zip` for archiving, `softprops/action-gh-release` or `gh release create` for release creation.

**Source of truth:** `docs/superpowers/specs/2026-04-16-whereami-ci-releases-design.md`

---

## Notes to the implementer

- This is an infrastructure/CI task. "Testing" means verifying the YAML is valid and the workflow triggers correctly — there are no unit tests.
- The project uses Zig 0.15.2. On GitHub Actions, install Zig using `mlugg/setup-zig@v2` (or equivalent well-maintained action). Pin to `0.15.2`.
- All extern function declarations in the project are hand-written (`extern "c"` / `extern "ole32"` etc.) — there are no `@cImport`/`@cInclude` calls. This means cross-compilation does NOT require system headers (no `libdbus-1-dev` needed on the Linux runner for the Linux target, no Windows SDK for the Windows target).
- The `zig build bundle` step in `build.zig` only fires when the target OS is `.macos`. It uses shell commands (`mkdir`, `cp`, `codesign`, `ln -s`), so it only works on a macOS runner.
- Both macOS targets are built on the same runner, so `zig-out/` must be cleaned between builds (both output to the same directory).
- The workflow file goes at `.github/workflows/release.yml`.

---

## File to create

- `.github/workflows/release.yml`

---

### Task 1: Create the workflow file with trigger configuration and Zig setup

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create the directory structure**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Create `.github/workflows/release.yml` with the workflow skeleton**

Write the file with:

```yaml
name: Build and Release

on:
  push:
    branches: [main]
    tags: ['v*']

permissions:
  contents: write

jobs:
  build-macos:
    runs-on: macos-latest
    strategy:
      matrix:
        target: [aarch64-macos, x86_64-macos]
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2
      - name: Build
        run: echo "placeholder"

  build-linux-windows:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include:
          - target: x86_64-linux
            artifact_name: whereami
            archive_ext: tar.gz
          - target: aarch64-linux
            artifact_name: whereami
            archive_ext: tar.gz
          - target: x86_64-windows
            artifact_name: whereami.exe
            archive_ext: zip
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2
      - name: Build
        run: echo "placeholder"
```

This establishes the trigger model (push to main + tag push), permissions (contents: write for release creation), two jobs with their matrices, and Zig installation. The build steps are placeholders — filled in by Tasks 2 and 3.

- [ ] **Step 3: Verify YAML is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))"
```

If `pyyaml` is not available, use:

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml')"
```

Either should exit without error.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add workflow skeleton with triggers and Zig setup"
```

---

### Task 2: Implement the macOS build job

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Replace the macOS job's placeholder build step with the full build and archive sequence**

The macOS job needs to, for each matrix target:

1. Clean `zig-out/` (in case a previous matrix entry left artifacts — matrix entries run in parallel on separate runners, but being explicit doesn't hurt).
2. Build with the target triple: `zig build bundle -Dtarget=${{ matrix.target }}` — this builds the binary AND creates the `.app` bundle with codesigning and symlink.
3. Determine the version string: if triggered by a tag, extract it from `${{ github.ref_name }}` (e.g., `v0.1.0`). If triggered by a push to main, use `dev-${{ github.sha }}` (short form) or just `dev`.
4. Create the archive directory and populate it:
   ```bash
   ARCHIVE_DIR="whereami-${VERSION}-${{ matrix.target }}"
   mkdir -p "$ARCHIVE_DIR"
   cp -R zig-out/whereami.app "$ARCHIVE_DIR/"
   ln -s whereami.app/Contents/MacOS/whereami "$ARCHIVE_DIR/whereami"
   tar czf "${ARCHIVE_DIR}.tar.gz" "$ARCHIVE_DIR"
   ```
5. Upload the archive as a workflow artifact using `actions/upload-artifact@v4`:
   ```yaml
   - uses: actions/upload-artifact@v4
     with:
       name: whereami-${{ matrix.target }}
       path: whereami-*.tar.gz
   ```

The full steps section for the macOS job should look like:

```yaml
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Build macOS bundle
        run: |
          rm -rf zig-out
          zig build bundle -Dtarget=${{ matrix.target }}

      - name: Package archive
        run: |
          VERSION="${{ github.ref_type == 'tag' && github.ref_name || format('dev-{0}', github.sha) }}"
          ARCHIVE_DIR="whereami-${VERSION}-${{ matrix.target }}"
          mkdir -p "${ARCHIVE_DIR}"
          cp -R zig-out/whereami.app "${ARCHIVE_DIR}/"
          ln -s whereami.app/Contents/MacOS/whereami "${ARCHIVE_DIR}/whereami"
          tar czf "${ARCHIVE_DIR}.tar.gz" "${ARCHIVE_DIR}"
          echo "ARCHIVE=${ARCHIVE_DIR}.tar.gz" >> "$GITHUB_ENV"

      - uses: actions/upload-artifact@v4
        with:
          name: whereami-${{ matrix.target }}
          path: ${{ env.ARCHIVE }}
```

- [ ] **Step 2: Verify YAML is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" || ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml')"
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: implement macOS build and archive steps"
```

---

### Task 3: Implement the Linux/Windows build job

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Replace the Linux/Windows job's placeholder build step**

The Linux/Windows job uses a matrix with `include` to differentiate behavior per target. For each matrix entry:

1. Build: `zig build -Dtarget=${{ matrix.target }}` (NOT `bundle` — that's macOS only).
2. Determine version string (same logic as macOS job).
3. Create archive:
   - For `.tar.gz` (Linux targets):
     ```bash
     ARCHIVE_DIR="whereami-${VERSION}-${{ matrix.target }}"
     mkdir -p "${ARCHIVE_DIR}"
     cp "zig-out/bin/${{ matrix.artifact_name }}" "${ARCHIVE_DIR}/"
     tar czf "${ARCHIVE_DIR}.tar.gz" "${ARCHIVE_DIR}"
     ```
   - For `.zip` (Windows target):
     ```bash
     ARCHIVE_DIR="whereami-${VERSION}-${{ matrix.target }}"
     mkdir -p "${ARCHIVE_DIR}"
     cp "zig-out/bin/${{ matrix.artifact_name }}" "${ARCHIVE_DIR}/"
     zip -r "${ARCHIVE_DIR}.zip" "${ARCHIVE_DIR}"
     ```
4. Upload as workflow artifact.

A clean way to handle both archive types in one step:

```yaml
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2

      - name: Build
        run: |
          rm -rf zig-out
          zig build -Dtarget=${{ matrix.target }}

      - name: Package archive
        run: |
          VERSION="${{ github.ref_type == 'tag' && github.ref_name || format('dev-{0}', github.sha) }}"
          ARCHIVE_DIR="whereami-${VERSION}-${{ matrix.target }}"
          mkdir -p "${ARCHIVE_DIR}"
          cp "zig-out/bin/${{ matrix.artifact_name }}" "${ARCHIVE_DIR}/"
          if [ "${{ matrix.archive_ext }}" = "zip" ]; then
            zip -r "${ARCHIVE_DIR}.zip" "${ARCHIVE_DIR}"
            echo "ARCHIVE=${ARCHIVE_DIR}.zip" >> "$GITHUB_ENV"
          else
            tar czf "${ARCHIVE_DIR}.tar.gz" "${ARCHIVE_DIR}"
            echo "ARCHIVE=${ARCHIVE_DIR}.tar.gz" >> "$GITHUB_ENV"
          fi

      - uses: actions/upload-artifact@v4
        with:
          name: whereami-${{ matrix.target }}
          path: ${{ env.ARCHIVE }}
```

- [ ] **Step 2: Verify YAML is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" || ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml')"
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: implement Linux/Windows build and archive steps"
```

---

### Task 4: Add the release job (tag-triggered only)

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add a `release` job that runs only on tag push, after both build jobs**

The release job:
1. Only runs when the trigger is a tag: `if: github.ref_type == 'tag'`
2. Depends on both build jobs: `needs: [build-macos, build-linux-windows]`
3. Downloads all artifacts using `actions/download-artifact@v4`
4. Creates a GitHub Release and attaches all archives using `softprops/action-gh-release@v2`

Add this job to the workflow:

```yaml
  release:
    if: github.ref_type == 'tag'
    needs: [build-macos, build-linux-windows]
    runs-on: ubuntu-latest
    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts
          merge-multiple: true

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: artifacts/*
          generate_release_notes: true
```

Key points:
- `merge-multiple: true` on `download-artifact` puts all artifacts (from both build jobs) into a flat `artifacts/` directory.
- `softprops/action-gh-release` automatically uses the tag name as the release title.
- `generate_release_notes: true` auto-generates notes from commits since the last tag.
- The `permissions: contents: write` at the top of the workflow covers the token permissions needed for release creation.

- [ ] **Step 2: Verify YAML is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" || ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml')"
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release job for tag-triggered GitHub Releases"
```

---

### Task 5: End-to-end verification and push

**Files:**
- Read-only verification of `.github/workflows/release.yml`

- [ ] **Step 1: Re-read the complete workflow file top to bottom**

Check:
- Two trigger events: `push` to `main` and `push` of `v*` tags.
- `permissions: contents: write` is present.
- Three jobs: `build-macos`, `build-linux-windows`, `release`.
- macOS job matrix covers `aarch64-macos` and `x86_64-macos`.
- Linux/Windows job matrix covers `x86_64-linux`, `aarch64-linux`, `x86_64-windows`.
- macOS job uses `zig build bundle -Dtarget=...`.
- Linux/Windows job uses `zig build -Dtarget=...` (NOT `bundle`).
- Archive naming uses version from tag (or `dev-<sha>` on main push).
- macOS archives contain `.app` bundle + `whereami` symlink.
- Linux archives contain `whereami` binary.
- Windows archive is `.zip` containing `whereami.exe`.
- Release job has `if: github.ref_type == 'tag'` and `needs: [build-macos, build-linux-windows]`.
- Release job downloads artifacts and creates release with `generate_release_notes: true`.

- [ ] **Step 2: Verify YAML is valid one final time**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" || ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml')"
```

- [ ] **Step 3: Verify no stray files were created**

```bash
git status
```

Only `.github/workflows/release.yml` should be tracked/modified.

- [ ] **Step 4: Push to main to trigger the CI-only run**

```bash
git push origin main
```

This will trigger the workflow on the `main` branch. All 5 builds should run (but no release will be created since it's not a tag push). Check the Actions tab on GitHub to verify all jobs pass.

**IMPORTANT:** Do NOT create a tag or release yet. The first push to main is a dry run to verify the workflow works. If any build fails, diagnose and fix before tagging.

- [ ] **Step 5: If all CI jobs pass, report success**

Do NOT tag a release — that's the user's call. Report:
- Which jobs passed/failed
- Link to the Actions run (if available via `gh`)
- Any issues discovered

---

## Done criteria

- `.github/workflows/release.yml` exists and is valid YAML.
- Pushing to `main` triggers builds for all 5 targets (no release created).
- Pushing a `v*` tag builds all 5 targets and creates a GitHub Release with all 5 archives attached.
- macOS archives are `.tar.gz` containing `.app` bundle + `whereami` symlink.
- Linux archives are `.tar.gz` containing the `whereami` binary.
- Windows archive is `.zip` containing `whereami.exe`.
- Archive filenames include the version from the tag.
- No extra files, no stray artifacts, no unnecessary dependencies.
