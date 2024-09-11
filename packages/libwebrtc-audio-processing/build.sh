TERMUX_PKG_HOMEPAGE=https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/
TERMUX_PKG_DESCRIPTION="A library containing the AudioProcessing module from the WebRTC project"
TERMUX_PKG_LICENSE="BSD 3-Clause"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=0.3.1
TERMUX_PKG_REVISION=2
TERMUX_PKG_SRCURL=https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing/-/archive/9a202fb8c218223d24dfbbe6130053c68111e97a/webrtc-audio-processing-9a202fb8c218223d24dfbbe6130053c68111e97a.tar.gz
TERMUX_PKG_SHA256=a7b6afbf69e29deaf01b7a9cf1fba8227d1383e32f072c28cbb9fecb625ace1a
TERMUX_PKG_DEPENDS="libc++"
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_pre_configure() {
	LDFLAGS+=" $($CC -print-libgcc-file-name)"
}
