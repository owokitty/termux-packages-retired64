TERMUX_PKG_HOMEPAGE=https://www.gnu.org/software/sed/
TERMUX_PKG_DESCRIPTION="GNU stream editor for filtering/transforming text"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=4.9
TERMUX_PKG_REVISION=1
TERMUX_PKG_SRCURL=https://mirrors.kernel.org/gnu/sed/sed-${TERMUX_PKG_VERSION}.tar.xz
TERMUX_PKG_SHA256=6e226b732e1cd739464ad6862bd1a1aba42d7982922da7a53519631d24975181
TERMUX_PKG_ESSENTIAL=true
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_GROUPS="base-devel"

TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
ac_cv_func_nl_langinfo=no
ac_cv_header_langinfo_h=no
am_cv_langinfo_codeset=no
gl_cv_func_setlocale_works=yes
"

termux_step_pre_configure() {
	CFLAGS+=" -D__USE_FORTIFY_LEVEL=2"
}

termux_step_post_configure() {
	touch -d "next hour" $TERMUX_PKG_SRCDIR/doc/sed.1
}

termux_step_post_massage() {
	if $TERMUX_ON_DEVICE_BUILD; then
		return
	fi
	# installing sed for Android aarch64 into Ubuntu amd64 docker builder's 
	# $TERMUX_PREFIX/bin folder and failing to remove it afterward will result in frequent 
	# "/data/data/com.termux/files/usr/bin/sed: cannot execute binary file: Exec format error"
	# when building other packages afterward (for example libtheora)
	rm $TERMUX_PREFIX/bin/sed
}