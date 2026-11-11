---
worth: yes
where: files/build-deps.sh
added: 2026-11-12
---
# libcurl's default CA bundle path exists only on RHEL-family systems

curl's `configure` runs on the CentOS 7 base and picks up `/etc/pki/tls/certs/ca-bundle.crt` as the
compiled-in default CA bundle (`curl-config --ca`). The universal agent ships that static libcurl, and the
agent passes no CA file of its own unless `CACertificates` (core, used by web service DCIs and the
prometheus subagent) or `CA` (netsvc) is configured, so `SetupLibCURLTrust` in `src/libnetxms/curl.cpp`
leaves libcurl on that default.

On Debian 12, Ubuntu 24.04 and openSUSE Leap 15.6, with the system CA store installed, every verified HTTPS
request then fails with `curl: (77) error adding trust anchors from file: /etc/pki/tls/certs/ca-bundle.crt`.
The same curl binary returns 200 on Rocky 9, and on Debian/Ubuntu once `--cacert
/etc/ssl/certs/ca-certificates.crt` is passed. Tested with `/opt/libcurl/bin/curl` from the image.

Fix options:

- agent side (netxms-master): when no bundle is configured on a non-Windows system, have
  `SetupLibCURLTrust` use the first existing well-known file: `/etc/ssl/certs/ca-certificates.crt`
  (Debian/Ubuntu/Arch/Gentoo), `/etc/pki/tls/certs/ca-bundle.crt` (RHEL/Fedora),
  `/etc/ssl/ca-bundle.pem` (SUSE), `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem` (RHEL 7+),
  `/etc/ssl/cert.pem` (Alpine). Harmless for native distro builds, whose libcurl already knows its path;
- builder side: configure curl with `--without-ca-bundle --without-ca-path --with-ca-fallback` and give
  OpenSSL a system `--openssldir`. Weaker: no single directory works on every distribution, and static
  OpenSSL would then read the host's `openssl.cnf`.
