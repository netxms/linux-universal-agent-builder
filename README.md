# Universal Linux agent build environment

Container-based build of the two universal Linux agent variants:

* **dynamic** — `nxagentd` plus shared libraries and subagents, packed as
  `nxagent-<version>-<suffix>.apkg` (self-extracting installer) and `.tar.gz`
* **static** — single `nxagentd` binary that depends on glibc only, linked by
  `src/agent/core/static_link.sh` and shipped gzip-compressed as
  `nxagentd-<version>-<suffix>-static.gz`

The image is based on PyPA manylinux (CentOS 7 userland, glibc 2.17, GCC 10 from
devtoolset), so the output runs on any distribution with glibc 2.17 or newer. All
third-party libraries (OpenSSL, libcurl, libssh, PCRE2, zlib, expat) are built from
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
Dockerfile), run `docker build -t netxms-agent-builder .` in this repository.

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

## Raising the glibc floor

To switch to glibc 2.28 (AlmaLinux 8 userland, newer toolchain, drops RHEL 7 /
Ubuntu 16.04 / Debian 9 targets):

```sh
docker build --platform linux/amd64 \
   --build-arg BASE_IMAGE=quay.io/pypa/manylinux_2_28_x86_64 \
   --build-arg GLIBC_MAX=2.28 --build-arg GLIBCXX_MAX=3.4.25 ...
```

`GLIBC_MAX` / `GLIBCXX_MAX` are the floors enforced by `check-elf.sh` on every
produced ELF file; the build fails if a binary needs a newer symbol version or
depends on a shared library outside glibc, libstdc++/libgcc and the package itself.
The static variant is checked with `--libc-only`.

## Reproducibility

Everything that goes into the image is pinned:

* manylinux base images by tag and digest, one per architecture (`base-*` stages
  at the top of the Dockerfile);
* third-party library versions, with tarballs verified against the SHA-256 values
  in the Dockerfile;
* GitHub Actions in `.github/workflows/image.yml` by commit SHA.

The CentOS 7 packages installed with yum come from the frozen 7.9.2009 vault.
To update a base image, take the new tag's digest from quay.io and change both
the tag and the digest.

## Published images

`.github/workflows/image.yml` builds each architecture on a native GitHub runner
(`ubuntu-24.04` for x86_64 and i686, `ubuntu-24.04-arm` for aarch64), then
combines them into one manifest list. Pushes to `master` publish `latest` and
`sha-<commit>`; `v*` tags publish `<version>` and `<major>.<minor>`. Pull requests
build all three architectures without pushing.
