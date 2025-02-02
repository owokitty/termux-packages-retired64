TERMUX_PKG_HOMEPAGE=https://github.com/google/flatbuffers
TERMUX_PKG_DESCRIPTION="Memory Efficient Serialization Library"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@termux"
# major version =23 required by libarrow-cpp 17.0.0 if this package is built before that one
TERMUX_PKG_VERSION="23.5.26"
TERMUX_PKG_SRCURL=https://github.com/google/flatbuffers/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=1cce06b17cddd896b6d73cc047e36a254fb8df4d7ea18a46acf16c4c0cd3f3f3
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_DEPENDS="libc++"

TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DFLATBUFFERS_BUILD_SHAREDLIB=ON
-DFLATBUFFERS_BUILD_TESTS=OFF
"
