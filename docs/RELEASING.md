# Releasing fuetem-deb

This document covers everything needed to push a new version of fuetem-deb to GitHub and trigger the .deb build.

## Prerequisites

- GitHub remote uses HTTPS: `https://github.com/invisi101/fuetem-deb.git`
- GitHub Actions workflow at `.github/workflows/build-deb.yml` builds the .deb automatically when a tag starting with `v` is pushed
- The .deb is built on Ubuntu and attached to a GitHub Release

## Step-by-step release process

### 1. Make your changes

Edit whatever you need in `~/dev/fuetem-deb/`. Test locally with:

```bash
cd ~/dev/fuetem-deb
bash -n bin/fuetem lib/*.sh        # syntax check all scripts
FUETEM_LIB_DIR="$(pwd)/lib" bash bin/fuetem  # run from dev checkout
```

Note: if fuetem-arch is installed to `~/.local/` or `/usr/`, the launcher will pick that up instead of your dev copy. Use the `FUETEM_LIB_DIR` override above.

Also verify no Arch-specific commands leaked in:

```bash
grep -rn 'pacman\|paccache\|checkupdates\|yay\|pacsave\|pacnew\|arch-audit\|aide\.wrapper' lib/ bin/
```

### 2. Commit and push to GitHub

```bash
cd ~/dev/fuetem-deb
git add <changed files>
git commit -m "description of changes"
git push origin main
```

### 3. Decide the new version number

Look at the current version:

```bash
head -1 debian/changelog
```

Bump it: patch (1.0.1 → 1.0.2) for fixes, minor (1.0.1 → 1.1.0) for new features, major (1.0.1 → 2.0.0) for breaking changes.

### 4. Update debian/changelog

Add a new entry at the top of `debian/changelog`. The format is strict — follow it exactly:

```
fuetem-deb (X.Y.Z-1) unstable; urgency=medium

  * Brief description of changes.

 -- invisi101 <invisi101@users.noreply.github.com>  Day, DD Mon YYYY HH:MM:SS +0000
```

The date format must be RFC 2822. Generate it with:

```bash
date -R
```

Important: the line before `--` must be exactly two spaces followed by `*`. The `--` line must start with exactly one space.

### 5. Commit the changelog update

```bash
git add debian/changelog
git commit -m "Release vX.Y.Z: brief description"
git push origin main
```

### 6. Tag and push the release

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

This triggers the GitHub Actions workflow which:
1. Spins up an Ubuntu runner
2. Installs `build-essential`, `debhelper`, `devscripts`
3. Runs `dpkg-buildpackage` to create the `.deb`
4. Creates a GitHub Release with the `.deb` attached

### 7. Verify

```bash
# Check the workflow status
gh run list --limit 1

# Watch it if it's still running
gh run watch

# Check the release has the .deb attached
gh release view vX.Y.Z
```

If the build fails, check the logs:

```bash
gh run view <RUN_ID> --log-failed
```

Fix the issue, commit, delete the tag, retag, and push again:

```bash
git tag -d vX.Y.Z
git push origin :refs/tags/vX.Y.Z
# make fixes, commit, push
git tag vX.Y.Z
git push origin vX.Y.Z
```

### 8. Update README if needed

If the version number appears in the README install instructions (e.g. `sudo apt install ./fuetem-deb_1.0.0-1_all.deb`), update it to match the new version.

## Quick reference (copy-paste version)

Replace `X.Y.Z` with your new version and `DESCRIPTION` with a brief summary:

```bash
# In ~/dev/fuetem-deb after committing your changes:
git push origin main
# Update debian/changelog with new version entry
git add debian/changelog && git commit -m "Release vX.Y.Z: DESCRIPTION" && git push origin main
git tag vX.Y.Z && git push origin vX.Y.Z
```

Then wait for GitHub Actions to build the .deb and create the release.

## Troubleshooting

### GitHub Actions build fails with "Unmet build dependencies"

The workflow needs to install all build deps. Check `.github/workflows/build-deb.yml` and add any missing packages to the `apt-get install` line.

### dpkg-buildpackage fails with changelog errors

The changelog format is very strict. Common mistakes:
- Wrong date format (must be RFC 2822: `Sat, 07 Mar 2026 12:00:00 +0000`)
- Missing space before `--` on the maintainer line
- Missing two spaces before `*` on the change lines
- Version in changelog doesn't match what you expect

### Tag pushed but no workflow ran

GitHub Actions only triggers once per tag name. If you deleted and recreated the same tag, bump the version number instead (e.g. `v1.0.2` instead of reusing `v1.0.1`).

### .deb installs but fuetem command not found

The .deb installs to `/usr/bin/fuetem`. Check it exists:

```bash
dpkg -L fuetem-deb | grep bin
```

## Syncing changes from fuetem-arch

When you make changes to fuetem-arch that should also apply to fuetem-deb, remember:

- `bin/fuetem`, `lib/lib.sh`, `lib/vpncheck.sh`, `lib/scan-secrets.sh`, `lib/sysmonitor.sh` are identical — copy them directly
- `lib/main.sh` and `lib/integrity_check.sh` are different — port the changes manually, translating Arch commands to Debian equivalents
- After copying/porting, always run `grep -rn 'pacman\|yay\|paccache\|checkupdates\|arch-audit\|aide\.wrapper' lib/ bin/` to make sure no Arch-specific commands leaked in
