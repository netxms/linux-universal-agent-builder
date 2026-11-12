# Build environment for universal Linux agent packages.
#
# Based on PyPA manylinux: an old glibc userland (2.17 for manylinux2014,
# 2.28 for manylinux_2_28) with a modern GCC from devtoolset/gcc-toolset on
# top. Binaries built here run on any distribution with glibc >= that floor.
# All third-party libraries the agent links against are built from pinned
# sources as static, position-independent archives under /opt/<name>, so
# shipped binaries take only glibc and the C++ runtime from the system.
#
# Build:
#   docker build -t netxms-agent-builder .
# For the glibc 2.28 floor (manylinux_2_28, AlmaLinux 8 userland, GCC 14):
#   docker build --build-arg GLIBC=2.28 -t netxms-agent-builder:glibc2.28 .
# For aarch64 (native arm64 host, or qemu binfmt on x86_64):
#   docker build --platform linux/arm64 -t netxms-agent-builder:aarch64 .
# For 32-bit x86 (runs on any x86_64 host, no emulation needed):
#   docker build --platform linux/386 -t netxms-agent-builder:i686 .
#
# Commands run through manylinux-entrypoint, which switches to the 32-bit
# personality (linux32) on the i686 image so uname and OpenSSL's target
# detection see i686; on other images it is a plain exec.

# Base image for each glibc floor and target platform, pinned by digest. BuildKit
# pulls only the one selected by GLIBC and --platform.
ARG TARGETARCH
ARG GLIBC=2.17

FROM --platform=linux/amd64 quay.io/pypa/manylinux2014_x86_64:2026.11.07-1@sha256:62eeff30ef134a85ec0f97109e008a319b0315ca5e8a6d754ee771556c02622a AS base-glibc2.17-amd64
FROM --platform=linux/386 quay.io/pypa/manylinux2014_i686:2026.11.07-1@sha256:1e7424bb933e3de581e12da0db9487631ebb637d686010d6a69f54c9d1606af2 AS base-glibc2.17-386
FROM --platform=linux/arm64 quay.io/pypa/manylinux2014_aarch64:2026.11.07-1@sha256:101d2292840109c9d329fcfcd7b89b46f59e19ca23cbfdcf059fb389994665fc AS base-glibc2.17-arm64

FROM --platform=linux/amd64 quay.io/pypa/manylinux_2_28_x86_64:2026.11.07-1@sha256:9555ba6c479fa69a2aa80ad1dc57154a60d562b19df159361d9379a02beb1e36 AS base-glibc2.28-amd64
FROM --platform=linux/386 quay.io/pypa/manylinux_2_28_i686:2026.11.07-1@sha256:7a7fe196454a0e0b579d710760a754552e328cc3fc2713444419b0ab58e01c06 AS base-glibc2.28-386
FROM --platform=linux/arm64 quay.io/pypa/manylinux_2_28_aarch64:2026.11.07-1@sha256:cb37f0d66c8a75abb93cf6085cad1f1427cd7208f0c0fc48359bb1eea9924f21 AS base-glibc2.28-arm64

# Symbol version floors that check-elf.sh enforces on build output
FROM base-glibc2.17-${TARGETARCH} AS glibc2.17
ENV NXBUILD_GLIBC_MAX=2.17 \
    NXBUILD_GLIBCXX_MAX=3.4.19

FROM base-glibc2.28-${TARGETARCH} AS glibc2.28
ENV NXBUILD_GLIBC_MAX=2.28 \
    NXBUILD_GLIBCXX_MAX=3.4.25

FROM glibc${GLIBC}

# Third-party library versions and SHA-256 of release tarballs
ARG OPENSSL_VERSION=3.5.9
ARG OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
ARG ZLIB_VERSION=1.4
ARG ZLIB_SHA256=02dd159783677a749c04adbdd02b55b8a2bcc7e054f51b76b549199a916ad584
ARG EXPAT_VERSION=2.10.0
ARG EXPAT_SHA256=c624ba2998fc65df1163a49641ff3f9ab73138b11641d92c86bee0fb01b1bc7f
ARG PCRE2_VERSION=10.49
ARG PCRE2_SHA256=53c156e1ba416a20da8e65395daa132da0d80e76910424caca3fcdae7831d384
ARG CURL_VERSION=8.23.0
ARG CURL_SHA256=8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5
ARG LIBSSH_VERSION=0.12.2
ARG LIBSSH_SHA256=49560f677d96e3706a904ac2de1116e25f3680937d51e5c92198fcba4a1c1e9f

# yum is needed only for flex and two perl modules used by OpenSSL's Configure. CentOS 7
# (glibc 2.17 base) is EOL and vault.centos.org is unreliable, so use the kernel.org
# mirror of the vault; the sed matches nothing on the AlmaLinux 8 (glibc 2.28) base.
RUN sed -i -e 's#https\?://vault.centos.org/centos/\($releasever\|7\)/#https://archive.kernel.org/centos-vault/7.9.2009/#g' \
           -e 's#https\?://vault.centos.org/altarch/\($releasever\|7\)/#https://archive.kernel.org/centos-vault/altarch/7.9.2009/#g' \
           /etc/yum.repos.d/*.repo && \
    yum -y install perl-IPC-Cmd perl-Time-Piece flex && yum clean all

COPY files/build-deps.sh /usr/local/sbin/build-deps.sh
RUN OPENSSL_VERSION=${OPENSSL_VERSION} OPENSSL_SHA256=${OPENSSL_SHA256} \
    ZLIB_VERSION=${ZLIB_VERSION} ZLIB_SHA256=${ZLIB_SHA256} \
    EXPAT_VERSION=${EXPAT_VERSION} EXPAT_SHA256=${EXPAT_SHA256} \
    PCRE2_VERSION=${PCRE2_VERSION} PCRE2_SHA256=${PCRE2_SHA256} \
    CURL_VERSION=${CURL_VERSION} CURL_SHA256=${CURL_SHA256} \
    LIBSSH_VERSION=${LIBSSH_VERSION} LIBSSH_SHA256=${LIBSSH_SHA256} \
    manylinux-entrypoint /usr/local/sbin/build-deps.sh

COPY files/build.sh files/check-elf.sh /usr/local/sbin/

# Install prefix for the dynamic variant; world-writable so the container can
# run as the invoking user (--user) and leave the mounted tree owned by them.
RUN mkdir -p /opt/netxms /out && chmod 1777 /opt/netxms /out

WORKDIR /src
ENTRYPOINT ["manylinux-entrypoint", "/usr/local/sbin/build.sh"]
