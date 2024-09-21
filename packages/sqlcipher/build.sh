TERMUX_PKG_HOMEPAGE=https://github.com/sqlcipher/sqlcipher
TERMUX_PKG_DESCRIPTION="SQLCipher is an SQLite extension that provides 256 bit AES encryption of database files"
TERMUX_PKG_LICENSE="BSD"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="4.6.1"
TERMUX_PKG_SRCURL=https://github.com/sqlcipher/sqlcipher/archive/v$TERMUX_PKG_VERSION.tar.gz
TERMUX_PKG_SHA256=d8f9afcbc2f4b55e316ca4ada4425daf3d0b4aab25f45e11a802ae422b9f53a3
TERMUX_PKG_DEPENDS="libedit, openssl"
TERMUX_PKG_BUILD_DEPENDS="tcl"
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_UPDATE_TAG_TYPE="newest-tag"
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--enable-tempstore=yes
--with-tcl=${TERMUX_PREFIX}/lib
TCLLIBDIR=${TERMUX_PREFIX}/lib/tcl8.6/sqlite
"

termux_step_pre_configure() {
	# sqlcipher/src/src/tclsqlite.c:3170:10: error: call to undeclared function 'sqlite3_rekey'
	if [ -f "$TERMUX_PREFIX/include/sqlite3.h" ]; then
		mv  "$TERMUX_PREFIX/include/sqlite3.h"  "$TERMUX_PREFIX/include/sqlite3.h.bak"
	fi
	if [ -f "$TERMUX_PREFIX/include/sqlite3ext.h" ]; then
		mv  "$TERMUX_PREFIX/include/sqlite3ext.h"  "$TERMUX_PREFIX/include/sqlite3ext.h.bak"
	fi
	CPPFLAGS+=" -DSQLCIPHER_OMIT_LOG_DEVICE -DSQLITE_HAS_CODEC"
}

termux_step_post_massage() {
	if [ -f "$TERMUX_PREFIX/include/sqlite3.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/sqlite3.h.bak"  "$TERMUX_PREFIX/include/sqlite3.h"
	fi
	if [ -f "$TERMUX_PREFIX/include/sqlite3ext.h.bak" ]; then
		mv  "$TERMUX_PREFIX/include/sqlite3ext.h.bak"  "$TERMUX_PREFIX/include/sqlite3ext.h"
	fi
}