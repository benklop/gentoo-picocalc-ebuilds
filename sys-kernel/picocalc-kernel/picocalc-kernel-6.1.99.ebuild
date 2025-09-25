# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

KERNEL_IUSE_MODULES_SIGN=1

inherit kernel-build

DESCRIPTION="Linux kernel built for PicoCalc hardware with custom patches"
HOMEPAGE="https://github.com/benklop/picocalc-luckfox-kernel-6.1.99"
SRC_URI="https://github.com/benklop/picocalc-luckfox-kernel-6.1.99/archive/refs/heads/main.tar.gz -> ${P}.tar.gz"

S="${WORKDIR}/picocalc-luckfox-kernel-6.1.99-main"

LICENSE="GPL-2"
SLOT="${PV}"
KEYWORDS="~arm"
IUSE=""

RDEPEND="
	!sys-kernel/picocalc-kernel-bin:${SLOT}
"
BDEPEND=""
PDEPEND="
	>=virtual/dist-kernel-${PV}
"

QA_FLAGS_IGNORED="
	usr/src/linux-.*/scripts/gcc-plugins/.*.so
	usr/src/linux-.*/vmlinux
"

src_prepare() {
	# Apply all patches
	local patches=(
		"${FILESDIR}/001-mmc-core-sd-disable-vqmmc-regulator.patch"
		"${FILESDIR}/002-sound-add-pwm-subsystem.patch"
		"${FILESDIR}/003-sound-pwm-add-Kconfig.patch"
		"${FILESDIR}/004-sound-pwm-add-Makefile.patch"
		"${FILESDIR}/005-input-keyboard-add-picocalc-kconfig.patch"
		"${FILESDIR}/006-input-keyboard-add-picocalc-makefile.patch"
		"${FILESDIR}/007-misc-add-mculog-kconfig.patch"
		"${FILESDIR}/008-misc-add-mculog-makefile.patch"
		"${FILESDIR}/009-gpu-drm-tiny-add-ili9488-kconfig.patch"
		"${FILESDIR}/010-gpu-drm-tiny-add-ili9488-makefile.patch"
		"${FILESDIR}/011-of-configfs-kconfig.patch"
		"${FILESDIR}/012-of-configfs-makefile.patch"
	)

	for patch in "${patches[@]}"; do
		eapply "${patch}"
	done

	# Copy additional source files
	einfo "Copying additional source files..."
    [[ -d "${FILESDIR}/arch" ]] && cp -r "${FILESDIR}/arch"/* arch/ || die "Failed to copy devicetree files"
    [[ -d "${FILESDIR}/drivers" ]] && cp -r "${FILESDIR}/drivers"/* drivers/ || die "Failed to copy driver files"
    [[ -d "${FILESDIR}/sound" ]] && cp -r "${FILESDIR}/sound"/* sound/ || die "Failed to copy sound files"

	default

	# Set up kernel version
	local myversion="-picocalc"
	echo "CONFIG_LOCALVERSION=\"${myversion}\"" > "${T}"/version.config || die

	# Prepare the default config using the defconfig and fragments
	cp "${FILESDIR}/picocalc_rk3506_luckfox_defconfig" .config || die "Failed to copy defconfig"

	local merge_configs=(
		"${T}"/version.config
		"${FILESDIR}/gentoo-embedded.config"
		"${FILESDIR}/picocalc-rk3506-display.config"
		"${FILESDIR}/picocalc-rk3506-filesystems.config"
		"${FILESDIR}/picocalc-rk3506-keyboard.config"
		"${FILESDIR}/picocalc-rk3506-rtc.config"
		"${FILESDIR}/picocalc-rk3506-sound.config"
		"${FILESDIR}/picocalc-rk3506-terminal.config"
		"${FILESDIR}/picocalc-rk3506-wifi.config"
	)

	kernel-build_merge_configs "${merge_configs[@]}"
}