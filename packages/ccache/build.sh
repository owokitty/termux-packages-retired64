TERMUX_PKG_HOMEPAGE=https://ccache.samba.org
TERMUX_PKG_DESCRIPTION="Compiler cache for fast recompilation of C/C++ code"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="4.10.2"
TERMUX_PKG_SRCURL=https://github.com/ccache/ccache/releases/download/v$TERMUX_PKG_VERSION/ccache-$TERMUX_PKG_VERSION.tar.xz
TERMUX_PKG_SHA256=c0b85ddfc1a3e77b105ec9ada2d24aad617fa0b447c6a94d55890972810f0f5a
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="libandroid-spawn, libc++, libhiredis, xxhash, zlib, zstd"
TERMUX_PKG_BUILD_DEPENDS="fmt"

#[46/89] Building ASM object src/third_party/blake3/CMakeFiles/blake3.dir/blake3_sse2_x86-64_unix.S.o
#FAILED: src/third_party/blake3/CMakeFiles/blake3.dir/blake3_sse2_x86-64_unix.S.o
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DDEPS=LOCAL
-DENABLE_TESTING=OFF
-DHAVE_ASM_AVX2=FALSE
-DHAVE_ASM_AVX512=FALSE
-DHAVE_ASM_SSE2=FALSE
-DHAVE_ASM_SSE41=FALSE
"

termux_step_pre_configure() {
	LDFLAGS+=" -landroid-spawn"
}

termux_step_post_massage() {
	if $TERMUX_ON_DEVICE_BUILD; then
		return
	fi
	# installing ccache for Android aarch64 into Ubuntu amd64 docker builder's 
	# $TERMUX_PREFIX/bin folder and failing to remove it afterward will result in frequent 
	# "/data/data/com.termux/files/usr/bin/ccache: cannot execute binary file: Exec format error"
	# when building other packages afterward (for example libarrow-cpp)
	rm $TERMUX_PREFIX/bin/ccache
}