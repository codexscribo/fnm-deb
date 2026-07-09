# fnm-deb

Unofficial `.deb` packages for [fnm](https://github.com/Schniz/fnm) (Fast
Node Manager), built from the **official prebuilt release binaries**
published on the [Schniz/fnm releases page](https://github.com/Schniz/fnm/releases).

This repo does **not** compile fnm from source. It downloads the upstream
`fnm-linux.zip` / `fnm-arm64.zip` release assets, repackages the single
statically linked binary inside as `/usr/bin/fnm` in a Debian package, and
publishes the result as a GitHub Release — nothing more.

This project is **not affiliated with or endorsed by the fnm project**.

Building the package locally requires `docker`, `curl`, `unzip`, and `bash`.
The only Debian-specific step (`dpkg-deb --build`) runs inside a `debian:13`
container, so the build script works from macOS or any Linux host without
local Debian packaging tools installed.

## Install

```sh
curl -LO https://github.com/codexscribo/fnm-deb/releases/latest/download/fnm_<version>_amd64.deb
sudo apt install ./fnm_<version>_amd64.deb
```

Replace `amd64` with `arm64` on ARM systems, and `<version>` with the full
version string from the release you downloaded (e.g. `1.39.0-1`).

The package is named `fnm`, same as it would be if Debian/Ubuntu shipped
their own `fnm` package (they currently don't — see [Caveats](#caveats)), so
installing it upgrades or supersedes any existing `fnm` package. No special
flags are needed.

## Supported architectures

- `amd64`
- `arm64`

## Versioning

Package versions follow Debian's `<upstream_version>-<package_revision>`
convention, e.g. `1.39.0-1`. `<upstream_version>` is the upstream fnm
version; `<package_revision>` identifies how many times *this repackaging*
has been published for that same upstream version. A packaging-only fix can
be re-released as `1.39.0-2` without waiting for a new upstream fnm release.
Each `<version>-<revision>` combination is published as its own GitHub
Release, tagged e.g. `v1.39.0-2`, so every past revision stays downloadable —
grabbing the `latest` release always gets you the newest revision of the
newest version.

## How it works

1. **`scripts/build-deb.sh <version> <arch> [package_revision]`** downloads
   the matching upstream release zip, extracts the single `fnm` binary
   inside, and lays it out at `pkgroot/usr/bin/fnm`. It checks the binary's
   ELF header (via `file`) to confirm it's statically linked — upstream fnm
   Linux releases are `*-unknown-linux-musl` static-pie builds with zero
   runtime library dependencies, so this package ships no `Depends:` field
   at all; the check hard-fails the build if that assumption ever stops
   holding, rather than silently shipping a package missing a dependency it
   actually needs. It copies in
   `usr/share/doc/fnm/{copyright,changelog.Debian.gz}` — the static
   [`debian/copyright`](./debian/copyright) plus
   [`debian/changelog.template`](./debian/changelog.template) rendered with
   `sed` and gzipped — and renders
   [`debian/control.template`](./debian/control.template) with `sed` for the
   package version, architecture, and `Installed-Size`. It then runs a
   `debian:13` container just to invoke `dpkg-deb --build` (no `--platform`
   flag needed, since `dpkg-deb --build` only archives files — it never
   executes the packaged binary). This package is built once per
   architecture.
2. **`scripts/test-deb.sh <fnm-deb> <version>`** checks whether a stock
   `fnm` package exists in the target distro's own archive (`apt-cache show
   fnm`) and, if so, installs it first to exercise an upgrade path; today no
   target distro ships one, so this is a no-op check that stays correct
   automatically if that ever changes. It then installs the built `.deb`,
   checks that `fnm` runs and reports the right version, runs a functional
   smoke test (`fnm --help`, `fnm list`, `fnm env`), confirms `dpkg`
   metadata is correct, then removes the package and confirms full cleanup.
3. **`.github/workflows/release.yml`** runs on a daily schedule (and can be
   triggered manually). It resolves the latest upstream fnm release (or a
   specific version passed to `workflow_dispatch`), and auto-picks the next
   package revision for that version (or uses one passed explicitly via
   `workflow_dispatch`). The scheduled run skips entirely if a release for
   the resolved version already exists — its job is just to catch new
   upstream releases — but a manual `workflow_dispatch` run always proceeds,
   which is how you publish a packaging-only fix under a bumped revision. It
   then builds `fnm` `.deb`s for both architectures, tests each one across
   Ubuntu 22.04/24.04/26.04 and Debian 11/12/13, and only publishes a GitHub
   Release (as two assets, one per architecture) if every install/smoke-test
   combination passes.

## Caveats

- This is a repackaging of an upstream binary, not an independently built or
  audited package. Use at your own risk.
- fnm itself is licensed under [GPL-3.0](https://github.com/Schniz/fnm/blob/master/LICENSE).
  The MIT license in this repo applies only to the packaging scripts and CI
  here, not to fnm.
- There is currently no `fnm` package in Debian or Ubuntu's official
  archives, so there's no real "upgrade from the stock package" scenario to
  exercise today — `scripts/test-deb.sh` checks for one dynamically on every
  run and will exercise it automatically if a distro ever adds one. If a
  stock package does appear later, a subsequent `apt upgrade` won't
  auto-revert you to it once you've installed this one; you'd need to
  reinstall it explicitly.
- No APT repository is provided; the package is distributed only as a
  GitHub Release asset per architecture.
- Debian 11 (bullseye) is included in the test matrix since fnm's static-pie
  musl binary has no glibc floor to worry about, but bullseye is near its
  LTS end-of-life — if its Docker image's default `apt` sources stop
  resolving, that's a real Debian-archive-lifecycle issue to address in CI
  when it happens, not something papered over here.

## License

[MIT](./LICENSE) — applies to the packaging scripts and CI in this repo only,
not to fnm itself (see [Schniz/fnm](https://github.com/Schniz/fnm) for its
GPL-3.0 license).
