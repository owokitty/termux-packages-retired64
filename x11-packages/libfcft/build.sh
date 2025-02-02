TERMUX_PKG_HOMEPAGE=https://codeberg.org/dnkl/fcft
TERMUX_PKG_DESCRIPTION="A small font loading and glyph rasterization library"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="3.1.7"
TERMUX_PKG_SRCURL=https://codeberg.org/dnkl/fcft/archive/${TERMUX_PKG_VERSION[0]}.tar.gz
TERMUX_PKG_SHA256=0e29ea7edca4cf6f0ac6b4f6427a4606c184b3d809071e7d2f56fcc226574d30
TERMUX_PKG_DEPENDS="fontconfig, freetype, harfbuzz, libpixman, libwayland, libxkbcommon, utf8proc"
TERMUX_PKG_BUILD_DEPENDS="libtllist"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-Ddocs=disabled
"