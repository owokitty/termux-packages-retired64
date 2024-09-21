TERMUX_PKG_HOMEPAGE=https://mediaarea.net/en/MediaInfo
TERMUX_PKG_DESCRIPTION="Library for reading information from media files"
TERMUX_PKG_LICENSE="BSD 2-Clause"
TERMUX_PKG_LICENSE_FILE="../../../LICENSE"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="24.06"
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://github.com/MediaArea/MediaInfoLib/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=2a569dca09d953a38bf4ba0f47ba5415183c79436babb09e1202ebc3a54aa046
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="libc++, libcurl, libzen, zlib"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="--enable-shared --enable-static --with-libcurl"

termux_step_pre_configure() {
	# libmd provides $TERMUX_PREFIX/include/md5.h and sha1.h.
	# libmediainfo contains source files named md5.h and sha1.h that are completely different.
	# chaos ensues
	if [ -f "$TERMUX_PREFIX/include/md5.h" ]; then
		mv  "$TERMUX_PREFIX/include/md5.h"  "$TERMUX_PREFIX/include/md5.h.bak"
	fi
	if [ -f "$TERMUX_PREFIX/include/rmd160.h" ]; then
		mv  "$TERMUX_PREFIX/include/rmd160.h"  "$TERMUX_PREFIX/include/rmd160.h.bak"
	fi
	if [ -f "$TERMUX_PREFIX/include/ripemd.h" ]; then
		mv  "$TERMUX_PREFIX/include/ripemd.h"  "$TERMUX_PREFIX/include/ripemd.h.bak"
	fi
	if [ -f "$TERMUX_PREFIX/include/sha256.h" ]; then
		mv  "$TERMUX_PREFIX/include/sha256.h"  "$TERMUX_PREFIX/include/sha256.h.bak"
	fi
	if [ -f "$TERMUX_PREFIX/include/sha1.h" ]; then
		mv  "$TERMUX_PREFIX/include/sha1.h"  "$TERMUX_PREFIX/include/sha1.h.bak"
	fi
	if [ -f "$TERMUX_PREFIX/include/sha2.h" ]; then
		mv  "$TERMUX_PREFIX/include/sha2.h"  "$TERMUX_PREFIX/include/sha2.h.bak"
	fi
	if [ -f "$TERMUX_PREFIX/include/sha.h" ]; then
		mv  "$TERMUX_PREFIX/include/sha.h"  "$TERMUX_PREFIX/include/sha.h.bak"
	fi
	if [ -f "$TERMUX_PREFIX/include/md2.h" ]; then
		mv  "$TERMUX_PREFIX/include/md2.h"  "$TERMUX_PREFIX/include/md2.h.bak"
	fi
	if [ -f "$TERMUX_PREFIX/include/md4.h" ]; then
		mv  "$TERMUX_PREFIX/include/md4.h"  "$TERMUX_PREFIX/include/md4.h.bak"
	fi
	if [ -f "$TERMUX_PREFIX/include/sha512.h" ]; then
		mv  "$TERMUX_PREFIX/include/sha512.h"  "$TERMUX_PREFIX/include/sha512.h.bak"
	fi
	TERMUX_PKG_SRCDIR="${TERMUX_PKG_SRCDIR}/Project/GNU/Library"
	TERMUX_PKG_BUILDDIR="${TERMUX_PKG_SRCDIR}"
	cd "${TERMUX_PKG_SRCDIR}"
	./autogen.sh
	LDFLAGS+=" $($CC -print-libgcc-file-name)"
}

termux_step_post_massage() {
	# libmd provides $TERMUX_PREFIX/include/md5.h and sha1.h.
	# libmediainfo contains source files named md5.h and sha1.h that are completely different.
	# chaos ensues
	if [ -f "$TERMUX_PREFIX/include/md5.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/md5.h.bak"  "$TERMUX_PREFIX/include/md5.h"
	fi
	if [ -f "$TERMUX_PREFIX/include/rmd160.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/rmd160.h.bak"  "$TERMUX_PREFIX/include/rmd160.h"
	fi
	if [ -f "$TERMUX_PREFIX/include/ripemd.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/ripemd.h.bak"  "$TERMUX_PREFIX/include/ripemd.h"
	fi
	if [ -f "$TERMUX_PREFIX/include/sha256.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/sha256.h.bak"  "$TERMUX_PREFIX/include/sha256.h"
	fi
	if [ -f "$TERMUX_PREFIX/include/sha1.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/sha1.h.bak"  "$TERMUX_PREFIX/include/sha1.h"
	fi
	if [ -f "$TERMUX_PREFIX/include/sha2.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/sha2.h.bak"  "$TERMUX_PREFIX/include/sha2.h"
	fi
	if [ -f "$TERMUX_PREFIX/include/sha.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/sha.h.bak"  "$TERMUX_PREFIX/include/sha.h"
	fi
	if [ -f "$TERMUX_PREFIX/include/md2.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/md2.h.bak"  "$TERMUX_PREFIX/include/md2.h"
	fi
	if [ -f "$TERMUX_PREFIX/include/md4.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/md4.h.bak"  "$TERMUX_PREFIX/include/md4.h"
	fi
	if [ -f "$TERMUX_PREFIX/include/sha512.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/sha512.h.bak"  "$TERMUX_PREFIX/include/sha512.h"
	fi
}