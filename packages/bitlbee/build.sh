TERMUX_PKG_HOMEPAGE=https://www.bitlbee.org/
TERMUX_PKG_DESCRIPTION="An IRC to other chat networks gateway"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=3.6-1
TERMUX_PKG_SRCURL=https://github.com/bitlbee/bitlbee/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=81c6357fe08a8941221472e3790e2b351e3a8a41f9af0cf35395fdadbc8ac6cb
TERMUX_PKG_DEPENDS="ca-certificates, glib, libgcrypt, libgnutls"

termux_step_pre_configure() {
	# libmd provides $TERMUX_PREFIX/include/md5.h and sha1.h.
	# bitlbee contains source files named md5.h and sha1.h that are completely different.
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
	LDFLAGS+=" -lgcrypt"
}

termux_step_configure_autotools() {
	sh "$TERMUX_PKG_SRCDIR/configure" \
		--prefix=$TERMUX_PREFIX \
		$TERMUX_PKG_EXTRA_CONFIGURE_ARGS
}

termux_step_post_make_install() {
	make install-etc install-dev
}

termux_step_post_massage() {
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

termux_step_create_debscripts() {
	cat <<- EOF > ./postinst
	#!$TERMUX_PREFIX/bin/sh
	mkdir -p $TERMUX_PREFIX/var/lib/bitlbee
	EOF
}
