# Universal Linux agent build environment

Container-based build of the two universal Linux agent variants:

* **dynamic** — `nxagentd` plus shared libraries and subagents, packed as
  `nxagent-<version>-<suffix>.apkg` (self-extracting installer) and `.tar.gz`
* **static** — single `nxagentd` binary that depends on glibc only, linked by
  `src/agent/core/static_link.sh` and shipped gzip-compressed as
  `nxagentd-<version>-<suffix>-static.gz`

The image is based on PyPA manylinux and comes in two glibc floors (see
[glibc floors](#glibc-floors)); the default one (CentOS 7 userland, glibc 2.17, GCC 10
from devtoolset) produces output that runs on any distribution with glibc 2.17 or newer.
All third-party libraries (OpenSSL, libcurl, libssh, PCRE2, zlib, expat) are built from
pinned sources as static archives inside the image, so shipped binaries take only
glibc and the C++ runtime from the system.

## Usage

Prebuilt images for x86_64, i686 and aarch64 are published as a single multi-arch
image, `ghcr.io/netxms/linux-universal-agent-builder`. Run it from the root of a
NetXMS source checkout:

```sh
# build both variants from a clean checkout; results land in ./out
mkdir -p out
docker run --rm --user $(id -u):$(id -g) \
   -v "$PWD:/src" -v "$PWD/out:/out" ghcr.io/netxms/linux-universal-agent-builder
```

To build the image locally instead (e.g. after changing library versions in the
Dockerfile), run `docker build -t netxms-agent-builder .` in this repository; add
`--build-arg GLIBC=2.28` for the glibc 2.28 floor.

The source tree is built in place, so use a clean checkout (or `make distclean` first).
`build.sh` runs `build/prepare_release_build.sh` when `/src` is a git checkout and
plain `./reconf` otherwise.

Environment variables accepted by `build.sh` (pass with `-e`):

| Variable | Default | Meaning |
|---|---|---|
| `VARIANTS` | `dynamic static` | which variants to build |
| `SUFFIX` | `linux-<uname -m>` | package name suffix |
| `CONFIGURE_EXTRA` | | extra `configure` arguments for both variants |
| `STATIC_SUBAGENTS` | `default` | `--with-static-subagents-list` for the static variant |

## Other architectures

Docker pulls the image matching the host. aarch64 packages are built on an arm64
host (on x86_64 it works under qemu binfmt, but slowly).

32-bit x86 builds use the i686 image. It runs natively on any x86_64 host; the
`manylinux-entrypoint` wrapper switches to the 32-bit personality so `uname -m`
reports `i686` and the package suffix becomes `linux-i686`.

```sh
docker run --rm --platform linux/386 --user $(id -u):$(id -g) \
   -v "$PWD:/src" -v "$PWD/out:/out" ghcr.io/netxms/linux-universal-agent-builder
```

To build the image locally for another architecture, pass `--platform`; the
Dockerfile selects the matching manylinux base image:

```sh
docker build --platform linux/386 -t netxms-agent-builder:i686 .
```

## glibc floors

Each floor is published for all three architectures:

| Floor | Tag | Base | Toolchain | Runs on |
|---|---|---|---|---|
| glibc 2.17 | `latest`, `glibc2.17` | manylinux2014 (CentOS 7) | GCC 10 | RHEL/CentOS 7+, Debian 8+, Ubuntu 14.04+, SLES 12+ |
| glibc 2.28 | `glibc2.28` | manylinux_2_28 (AlmaLinux 8) | GCC 14 | RHEL 8+, Debian 10+, Ubuntu 20.04+, SLES 15 SP4+ |

Use the glibc 2.28 image when the targets don't include the older distributions:

```sh
docker run --rm --user $(id -u):$(id -g) \
   -v "$PWD:/src" -v "$PWD/out:/out" ghcr.io/netxms/linux-universal-agent-builder:glibc2.28
```

`GLIBC=2.17|2.28` selects the floor in the Dockerfile. Each floor sets
`NXBUILD_GLIBC_MAX` / `NXBUILD_GLIBCXX_MAX` (2.17 / 3.4.19 and 2.28 / 3.4.25), which
`check-elf.sh` enforces on every produced ELF file; the build fails if a binary needs a newer symbol version or
depends on a shared library outside glibc, libstdc++/libgcc and the package itself.
The static variant is checked with `--libc-only`.

## Reproducibility

Everything that goes into the image is pinned:

* manylinux base images by tag and digest, one per architecture (`base-*` stages
  at the top of the Dockerfile);
* third-party library versions, with tarballs verified against the SHA-256 values
  in the Dockerfile;
* GitHub Actions in `.github/workflows/image.yml` by commit SHA.

The CentOS 7 packages installed with yum in the glibc 2.17 image come from the frozen
7.9.2009 vault; the glibc 2.28 image installs them from the live AlmaLinux 8 repositories.
To update a base image, take the new tag's digest from quay.io and change both
the tag and the digest.

## Published images

`.github/workflows/image.yml` builds each architecture and glibc floor on a native
GitHub runner (`ubuntu-24.04` for x86_64 and i686, `ubuntu-24.04-arm` for aarch64),
then combines the architectures of each floor into one manifest list:

| Trigger | glibc 2.17 | glibc 2.28 |
|---|---|---|
| push to `master` | `latest`, `glibc2.17`, `sha-<commit>` | `glibc2.28`, `sha-<commit>-glibc2.28` |
| `v*` tag | `<version>`, `<major>.<minor>` | `<version>-glibc2.28`, `<major>.<minor>-glibc2.28` |

Pull requests build all six images without pushing.
