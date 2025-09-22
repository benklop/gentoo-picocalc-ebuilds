# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit meson flag-o-matic

DESCRIPTION="Android Debug Bridge daemon for Android debugging"
HOMEPAGE="https://developer.android.com/studio/command-line/adb"

# Use the same version and source as buildroot package
MY_PV="8.1.0+r23-8"
MY_FULL_PV="1%${MY_PV}"
MY_P="android-platform-system-core-debian-${MY_FULL_PV}"

SRC_URI="https://salsa.debian.org/android-tools-team/android-platform-system-core/-/archive/debian/${MY_FULL_PV}/${MY_P}.tar.gz"
S="${WORKDIR}/${MY_P}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="arm ~arm64"
IUSE="static secure +shell +tcp"

RDEPEND="
	dev-libs/openssl:=
"
DEPEND="${RDEPEND}"
BDEPEND="
	virtual/pkgconfig
"

# USE flags for configuration
# static - build statically linked binary
# secure - enable secure authentication 
# shell - enable shell access configuration
# tcp - enable TCP port configuration

src_prepare() {
	default
	
	# Apply Debian patches first (same as buildroot approach)
	if [[ -d debian/patches ]]; then
		local patch
		while IFS= read -r -d '' patch; do
			eapply "${patch}"
		done < <(find debian/patches -name "*.patch" -print0 | sort -z)
	fi
	
	# Copy buildroot patches to our files directory for application
	local buildroot_patches=(
		"0001-adb-libcrypto_utils-Switch-to-libopenssl.patch"
		"0002-adb-daemon-Support-linux.patch"
		"0003-adb-daemon-Support-custom-auth-command.patch"
		"0004-adb-Use-login-shell.patch"
		"0005-adb-Support-setting-adb-shell.patch"
		"0006-adb-daemon-Fix-build-issue-with-old-g.patch"
		"0007-adb-daemon-Handle-SIGINT.patch"
		"0008-adb-daemon-Fix-build-issue-with-musl-and-uclibc.patch"
	)
	
	# Apply buildroot patches if they exist in files directory
	local patch
	for patch in "${buildroot_patches[@]}"; do
		if [[ -f "${FILESDIR}/${patch}" ]]; then
			eapply "${FILESDIR}/${patch}"
		fi
	done
}

src_configure() {
	local emesonargs=()
	
	if use static; then
		append-flags -static
		append-ldflags -static
		emesonargs+=(
			-Ddefault_library=static
		)
	fi
	
	meson_src_configure
}

src_install() {
	meson_src_install
	
	# Install logcat utility (simple wrapper as in buildroot)
	if use shell; then
		cat > "${T}/logcat" <<-EOF || die
			#!/bin/sh
			tail -f \${@:--n 99999999} /var/log/messages
		EOF
		dobin "${T}/logcat"
		
		# Install shell configuration
		insinto /etc/profile.d
		cat > "${T}/adbd.sh" <<-EOF || die
			# ADB daemon shell configuration
			[ -x /bin/bash ] && export ADBD_SHELL=/bin/bash
		EOF
		
		# Configure TCP port if requested
		if use tcp; then
			echo 'export ADB_TCP_PORT=${ADB_TCP_PORT:-5555}' >> "${T}/adbd.sh" || die
		fi
		
		# Configure security if enabled
		if use secure; then
			echo 'export ADB_SECURE=1' >> "${T}/adbd.sh" || die
		fi
		
		doins "${T}/adbd.sh"
	fi
	
	# Install authentication script if secure mode and script available
	if use secure && [[ -f "${FILESDIR}/adbd-auth" ]]; then
		dobin "${FILESDIR}/adbd-auth"
	fi
}

pkg_postinst() {
	elog "Android ADB daemon has been installed."
	elog ""
	if use shell; then
		elog "Shell access is enabled. The daemon will use /bin/bash if available."
	fi
	if use tcp; then
		elog "TCP support is enabled. Set ADB_TCP_PORT environment variable"
		elog "to configure the port (default: 5555)."
	fi
	if use secure; then
		elog "Secure mode is enabled. You may need to configure authentication."
		elog "Place your ADB public keys in /adb_keys file."
	fi
	elog ""
	elog "To start the ADB daemon, run: adbd"
	elog "Note: This package provides the daemon only. You'll need the ADB"
	elog "client from android-tools package to connect to it."
}