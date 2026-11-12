---
worth: later
where: Dockerfile
added: 2026-11-12
---
# manylinux2014 base images lose upstream support on 2027-05-04

PyPA will stop building manylinux2014 images when Python 3.16 is added, planned for 2027-05-04
(https://github.com/pypa/manylinux/issues/1925). After that the pinned `base-*` digests keep working only
as long as quay.io serves them, and the CentOS 7 toolchain (GCC 10) and userland get no further updates.

Options:

- keep the glibc 2.17 floor on the last 2014 images, copied to a registry we control (e.g. ghcr) so the
  pins cannot disappear;
- retire the glibc 2.17 images and make the glibc 2.28 one (manylinux_2_28, AlmaLinux 8, GCC 14), already
  published as `glibc2.28`, the default; this drops RHEL/CentOS 7, Debian 8–9 and Ubuntu 14.04–18.04.

Unknown that settles it: whether those old targets are actually required by customers. The original
commit in netxms-master (61fbba6655) chose 2.17 deliberately but recorded no reason; ask Victor.
