TERMUX_PKG_HOMEPAGE=https://aomedia.org/
TERMUX_PKG_DESCRIPTION="AV1 Video Codec Library"
TERMUX_PKG_LICENSE="BSD 2-Clause"
TERMUX_PKG_LICENSE_FILE="LICENSE, PATENTS"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="3.10.0"
TERMUX_PKG_SRCURL=https://storage.googleapis.com/aom-releases/libaom-${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=55ccb6816fb4b7d508d96a95b6e9cc3d2c0ae047f9f947dbba03720b56d89631
TERMUX_PKG_AUTO_UPDATE=true
# tests failing to build because package builds in-tree gtest instead of using termux gtest
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DBUILD_SHARED_LIBS=ON
-DCMAKE_INSTALL_LIBDIR=lib
-DENABLE_TESTS=OFF
"

termux_step_pre_configure() {
	# Do not forget to bump revision of reverse dependencies and rebuild them
	# after SOVERSION is changed.
	local _SOVERSION=3

	local a
	for a in LT_CURRENT LT_AGE; do
		local _${a}=$(sed -En 's/^set\('"${a}"'\s+([0-9]+).*/\1/p' \
				CMakeLists.txt)
	done
	local v=$(( _LT_CURRENT - _LT_AGE ))
	if [ ! "${_LT_CURRENT}" ] || [ "${v}" != "${_SOVERSION}" ]; then
		termux_error_exit "SOVERSION guard check failed."
	fi
}
