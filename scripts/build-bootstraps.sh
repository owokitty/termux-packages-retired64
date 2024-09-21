#!/usr/bin/env bash
# shellcheck disable=SC2039,SC2059

# Title:         build-bootstrap.sh
# Description:   A script to build bootstrap archives for the termux-app
#                from local package sources instead of debs published in
#                apt repo like done by generate-bootstrap.sh. It allows
#                bootstrap archives to be easily built for (forked) termux
#                apps without having to publish an apt repo first.
# Usage:         run "build-bootstrap.sh --help"
version=0.1.0

set -e

TERMUX_SCRIPTDIR=$(realpath "$(dirname "$0")/../")
. $(dirname "$(realpath "$0")")/properties.sh

BOOTSTRAP_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-tmp.XXXXXXXX")

# By default, bootstrap archives are compatible with Android >=7.0
# and <10.
BOOTSTRAP_ANDROID10_COMPATIBLE=false

# By default, bootstrap archives will be built for all architectures
# supported by Termux application.
# Override with option '--architectures'.
TERMUX_DEFAULT_ARCHITECTURES=("aarch64")
TERMUX_ARCHITECTURES=("${TERMUX_DEFAULT_ARCHITECTURES[@]}")

TERMUX_PACKAGE_MANAGER="apt"

TERMUX_PACKAGES_DIRECTORY="/home/builder/termux-packages"
TERMUX_BUILT_DEBS_DIRECTORY="$TERMUX_PACKAGES_DIRECTORY/output"
TERMUX_BUILT_PACKAGES_DIRECTORY="/data/data/.built-packages"

IGNORE_BUILD_SCRIPT_NOT_FOUND_ERROR=1
FORCE_BUILD_PACKAGES=0

# A list of packages to build
declare -a PACKAGES=()

# A list of already extracted packages
declare -a EXTRACTED_PACKAGES=()

# A list of options to pass to build-package.sh
declare -a BUILD_PACKAGE_OPTIONS=()

# Check for some important utilities that may not be available for
# some reason.
for cmd in ar awk curl grep gzip find sed tar xargs xz zip; do
	if [ -z "$(command -v $cmd)" ]; then
		echo "[!] Utility '$cmd' is not available in PATH."
		exit 1
	fi
done

# Build deb files for package and its dependencies deb from source for arch
build_package() {
	
	local return_value

	local package_arch="$1"
	local package_name="$2"

	local build_output

	# Build package from source
	# stderr will be redirected to stdout and both will be captured into variable and printed on screen
	cd "$TERMUX_PACKAGES_DIRECTORY"
	echo $'\n\n\n'"[*] Building '$package_name'..."
	exec 99>&1
	build_output="$("$TERMUX_PACKAGES_DIRECTORY"/build-package.sh "${BUILD_PACKAGE_OPTIONS[@]}" -a "$package_arch" "$package_name" 2>&1 | tee >(cat - >&99); exit ${PIPESTATUS[0]})";
	return_value=$?
	echo "[*] Building '$package_name' exited with exit code $return_value"
	exec 99>&-
	if [ $return_value -ne 0 ]; then
		echo "Failed to build package '$package_name' for arch '$package_arch'" 1>&2

		# Dependency packages may not have a build.sh, so we ignore the error.
		# A better way should be implemented to validate if its actually a dependency
		# and not a required package itself, by removing dependencies from PACKAGES array.
		if [[ $IGNORE_BUILD_SCRIPT_NOT_FOUND_ERROR == "1" ]] && [[ "$build_output" == *"No build.sh script at package dir"* ]]; then
			echo "Ignoring error 'No build.sh script at package dir'" 1>&2
			return 0
		fi
	fi

	return $return_value

}

# Extract *.deb files to the bootstrap root.
extract_debs() {

	local current_package_name
	local data_archive
	local control_archive
	local package_tmpdir
	local deb
	local file

	cd "$TERMUX_BUILT_DEBS_DIRECTORY"

	if [ -z "$(ls -A)" ]; then
		echo $'\n\n\n'"No debs found"
		return 1
	else
		echo $'\n\n\n'"Deb Files:"
		echo "\""
		ls
		echo "\""
	fi

	for deb in *.deb; do

		current_package_name="$(echo "$deb" | sed -E 's/^([^_]+).*/\1/' )"
		echo "current_package_name: '$current_package_name'"

		if [[ "$current_package_name" == *"-static" ]]; then
			echo "[*] Skipping static package '$deb'..."
			continue
		fi

		if [[ "$current_package_name" == *"cross"* ]]; then
			echo "[*] Skipping cross package '$current_package_name'..."
			continue
		fi

		if [[ " ${EXTRACTED_PACKAGES[*]} " == *" $current_package_name "* ]]; then
			echo "[*] Skipping already extracted package '$current_package_name'..."
			continue
		fi

		EXTRACTED_PACKAGES+=("$current_package_name")

		package_tmpdir="${BOOTSTRAP_PKGDIR}/${current_package_name}"
		mkdir -p "$package_tmpdir"
		rm -rf "$package_tmpdir"/*

		echo "[*] Extracting '$deb'..."
		(cd "$package_tmpdir"
			ar x "$TERMUX_BUILT_DEBS_DIRECTORY/$deb"

			# data.tar may have extension different from .xz
			if [ -f "./data.tar.xz" ]; then
				data_archive="data.tar.xz"
			elif [ -f "./data.tar.gz" ]; then
				data_archive="data.tar.gz"
			else
				echo "No data.tar.* found in '$deb'."
				return 1
			fi

			# Do same for control.tar.
			if [ -f "./control.tar.xz" ]; then
				control_archive="control.tar.xz"
			elif [ -f "./control.tar.gz" ]; then
				control_archive="control.tar.gz"
			else
				echo "No control.tar.* found in '$deb'."
				return 1
			fi

			# Extract files.
			tar xf "$data_archive" -C "$BOOTSTRAP_ROOTFS"

			if ! ${BOOTSTRAP_ANDROID10_COMPATIBLE}; then
				# Register extracted files.
				tar tf "$data_archive" | sed -E -e 's@^\./@/@' -e 's@^/$@/.@' -e 's@^([^./])@/\1@' > "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info/${current_package_name}.list"

				# Generate checksums (md5).
				tar xf "$data_archive"
				find data -type f -print0 | xargs -0 -r md5sum | sed 's@^\.$@@g' > "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info/${current_package_name}.md5sums"

				# Extract metadata.
				tar xf "$control_archive"
				{
					cat control
					echo "Status: install ok installed"
					echo
				} >> "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/status"

				# Additional data: conffiles & scripts
				for file in conffiles postinst postrm preinst prerm; do
					if [ -f "${PWD}/${file}" ]; then
						cp "$file" "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info/${current_package_name}.${file}"
					fi
				done
			fi
		)
	done

}

# Add termux bootstrap second stage files
add_termux_bootstrap_second_stage_files() {

	local package_arch="$1"

	echo $'\n\n\n'"[*] Adding termux bootstrap second stage files..."

	mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_BOOTSTRAP_CONFIG_DIR_PATH}"
	sed -e "s|@TERMUX_PREFIX@|${TERMUX_PREFIX}|g" \
		-e "s|@TERMUX_BOOTSTRAP_CONFIG_DIR_PATH@|${TERMUX_BOOTSTRAP_CONFIG_DIR_PATH}|g" \
		-e "s|@TERMUX_PACKAGE_MANAGER@|${TERMUX_PACKAGE_MANAGER}|g" \
		-e "s|@TERMUX_PACKAGE_ARCH@|${package_arch}|g" \
		"$TERMUX_SCRIPTDIR/scripts/bootstrap/termux-bootstrap-second-stage.sh" \
		> "${BOOTSTRAP_ROOTFS}/${TERMUX_BOOTSTRAP_CONFIG_DIR_PATH}/termux-bootstrap-second-stage.sh"
	chmod 700 "${BOOTSTRAP_ROOTFS}/${TERMUX_BOOTSTRAP_CONFIG_DIR_PATH}/termux-bootstrap-second-stage.sh"

	# TODO: Remove it when Termux app supports `pacman` bootstraps installation.
	sed -e "s|@TERMUX_PROFILE_D_PREFIX_DIR_PATH@|${TERMUX_PROFILE_D_PREFIX_DIR_PATH}|g" \
		-e "s|@TERMUX_BOOTSTRAP_CONFIG_DIR_PATH@|${TERMUX_BOOTSTRAP_CONFIG_DIR_PATH}|g" \
		"$TERMUX_SCRIPTDIR/scripts/bootstrap/01-termux-bootstrap-second-stage-fallback.sh" \
		> "${BOOTSTRAP_ROOTFS}/${TERMUX_PROFILE_D_PREFIX_DIR_PATH}/01-termux-bootstrap-second-stage-fallback.sh"
	chmod 600 "${BOOTSTRAP_ROOTFS}/${TERMUX_PROFILE_D_PREFIX_DIR_PATH}/01-termux-bootstrap-second-stage-fallback.sh"

}

# Final stage: generate bootstrap archive and place it to current
# working directory.
# Information about symlinks is stored in file SYMLINKS.txt.
create_bootstrap_archive() {

	echo $'\n\n\n'"[*] Creating 'bootstrap-${1}.zip'..."
	(cd "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}"
		# Do not store symlinks in bootstrap archive.
		# Instead, put all information to SYMLINKS.txt
		while read -r -d '' link; do
			echo "$(readlink "$link")←${link}" >> SYMLINKS.txt
			rm -f "$link"
		done < <(find . -type l -print0)

		zip -r9 "${BOOTSTRAP_TMPDIR}/bootstrap-${1}.zip" ./*
	)

	mv -f "${BOOTSTRAP_TMPDIR}/bootstrap-${1}.zip" "$TERMUX_PACKAGES_DIRECTORY/"

	echo "[*] Finished successfully (${1})."

}

set_build_bootstrap_traps() {

	#set traps for the build_bootstrap_trap itself
	trap 'build_bootstrap_trap' EXIT
	trap 'build_bootstrap_trap TERM' TERM
	trap 'build_bootstrap_trap INT' INT
	trap 'build_bootstrap_trap HUP' HUP
	trap 'build_bootstrap_trap QUIT' QUIT

	return 0

}

build_bootstrap_trap() {

	local build_bootstrap_trap_exit_code=$?
	trap - EXIT

	[ -h "$TERMUX_BUILT_PACKAGES_DIRECTORY" ] && rm -f "$TERMUX_BUILT_PACKAGES_DIRECTORY"
	[ -d "$BOOTSTRAP_TMPDIR" ] && rm -rf "$BOOTSTRAP_TMPDIR"

	[ -n "$1" ] && trap - "$1"; exit $build_bootstrap_trap_exit_code

}

show_usage() {

    cat <<'HELP_EOF'

build-bootstraps.sh is a script to build bootstrap archives for the
termux-app from local package sources instead of debs published in
apt repo like done by generate-bootstrap.sh. It allows bootstrap archives
to be easily built for (forked) termux apps without having to publish
an apt repo first.


Usage:
  build-bootstraps.sh [command_options]


Available command_options:
  [ -h  | --help ]             Display this help screen
  [ -f ]             Force build even if packages have already been built.
  [ --android10 ]
                     Generate bootstrap archives for Android 10+ for
                     apk packaging system.
  [ --architectures <architectures> ]
                     Override default list of architectures for which bootstrap
                     archives will be created. Multiple architectures should be
                     passed as comma-separated list.


The package name/prefix that the bootstrap is built for is defined by
TERMUX_APP_PACKAGE in 'scrips/properties.sh'. It defaults to 'com.termux'.
If package name is changed, make sure to run
`./scripts/run-docker.sh ./clean.sh` or pass '-f' to force rebuild of packages.

### Examples

Build default bootstrap archives for all supported archs:
./scripts/run-docker.sh ./scripts/build-bootstraps.sh &> build.log

Build default bootstrap archive for aarch64 arch only:
./scripts/run-docker.sh ./scripts/build-bootstraps.sh --architectures aarch64 &> build.log
HELP_EOF

echo $'\n'"TERMUX_APP_PACKAGE: \"$TERMUX_APP_PACKAGE\""
echo "TERMUX_PREFIX: \"${TERMUX_PREFIX[*]}\""
echo "TERMUX_ARCHITECTURES: \"${TERMUX_ARCHITECTURES[*]}\""

}

main() {

	local return_value

	while (($# > 0)); do
		case "$1" in
			-h|--help)
				show_usage
				return 0
				;;
			--android10)
				BOOTSTRAP_ANDROID10_COMPATIBLE=true
				;;
			--architectures)
				if [ $# -gt 1 ] && [ -n "$2" ] && [[ $2 != -* ]]; then
					TERMUX_ARCHITECTURES=()
					for arch in $(echo "$2" | tr ',' ' '); do
						TERMUX_ARCHITECTURES+=("$arch")
					done
					unset arch
					shift 1
				else
					echo "[!] Option '--architectures' requires an argument." 1>&2
					show_usage
					return 1
				fi
				;;
			-f)
				BUILD_PACKAGE_OPTIONS+=("-f")
				FORCE_BUILD_PACKAGES=1
				;;
			*)
				echo "[!] Got unknown option '$1'" 1>&2
				show_usage
				return 1
				;;
		esac
		shift 1
	done

	set_build_bootstrap_traps

	for package_arch in "${TERMUX_ARCHITECTURES[@]}"; do
		if [[ " ${TERMUX_DEFAULT_ARCHITECTURES[*]} " != *" $package_arch "* ]]; then
			echo "Unsupported architecture '$package_arch' for in architectures list: '${TERMUX_ARCHITECTURES[*]}'" 1>&2
			echo "Supported architectures: '${TERMUX_DEFAULT_ARCHITECTURES[*]}'" 1>&2
			return 1
		fi
	done

	for package_arch in "${TERMUX_ARCHITECTURES[@]}"; do

		# The termux_step_finish_build stores package version in .built-packages directory, but
		# its not arch independent. So instead we create an arch specific one and symlink it
		# to the .built-packages directory so that users can easily switch arches without having
		# to rebuild packages
		TERMUX_BUILT_PACKAGES_DIRECTORY_FOR_ARCH="$TERMUX_BUILT_PACKAGES_DIRECTORY-$package_arch"
		mkdir -p "$TERMUX_BUILT_PACKAGES_DIRECTORY_FOR_ARCH"

		if [ -f "$TERMUX_BUILT_PACKAGES_DIRECTORY" ] || [ -d "$TERMUX_BUILT_PACKAGES_DIRECTORY" ]; then
			rm -rf "$TERMUX_BUILT_PACKAGES_DIRECTORY"
		fi

		ln -sf "$TERMUX_BUILT_PACKAGES_DIRECTORY_FOR_ARCH" "$TERMUX_BUILT_PACKAGES_DIRECTORY"

		if [[ $FORCE_BUILD_PACKAGES == "1" ]]; then
			rm -f "$TERMUX_BUILT_PACKAGES_DIRECTORY_FOR_ARCH"/*
			rm -f "$TERMUX_BUILT_DEBS_DIRECTORY"/*
		fi



		BOOTSTRAP_ROOTFS="$BOOTSTRAP_TMPDIR/rootfs-${package_arch}"
		BOOTSTRAP_PKGDIR="$BOOTSTRAP_TMPDIR/packages-${package_arch}"

		# Create initial directories for $TERMUX_PREFIX
		if ! ${BOOTSTRAP_ANDROID10_COMPATIBLE}; then
			mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/etc/apt/apt.conf.d"
			mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/etc/apt/preferences.d"
			mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/info"
			mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/triggers"
			mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/updates"
			mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/log/apt"
			touch "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/available"
			touch "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/var/lib/dpkg/status"
		fi
		mkdir -p "${BOOTSTRAP_ROOTFS}/${TERMUX_PREFIX}/tmp"



		PACKAGES=()
		EXTRACTED_PACKAGES=()

		# Add ALL normal packages to build list
		# blacklist:
		# https://github.com/termux/termux-packages/issues/21130
		BLACKLIST=()
		BLACKLIST+=("audacious-plugins")
		BLACKLIST+=("audacious")
		BLACKLIST+=("bionic-host")
		BLACKLIST+=("cabal-install")
		BLACKLIST+=("chocolate-doom") # SDL2
		BLACKLIST+=("clvk")
		BLACKLIST+=("crypto-monitor")
		BLACKLIST+=("deadbeef") # msse3
		BLACKLIST+=("distant")
		BLACKLIST+=("dosbox-x")
		BLACKLIST+=("e2tools")
		BLACKLIST+=("emacs-x") # same
		BLACKLIST+=("emacs") # soundcard.h
		BLACKLIST+=("epiphany")
		BLACKLIST+=("feathernotes")
		BLACKLIST+=("featherpad")
		BLACKLIST+=("ffplay")
		BLACKLIST+=("findomain")
		BLACKLIST+=("fish")
		BLACKLIST+=("frida")
		BLACKLIST+=("gdal") # /bin/sh: 1: CMAKE_CXX_COMPILER_CLANG_SCAN_DEPS-NOTFOUND: not found
		BLACKLIST+=("gforth")
		BLACKLIST+=("ghc-libs")
		BLACKLIST+=("ghc")
		BLACKLIST+=("godot")
		BLACKLIST+=("grafana") 
		BLACKLIST+=("gw")
		BLACKLIST+=("hilbish")
		BLACKLIST+=("hunspell-fr")
		BLACKLIST+=("hunspell-hu")
		BLACKLIST+=("hunspell-nl")
		BLACKLIST+=("hunspell-ru")
		BLACKLIST+=("ices") # scripts/build/termux_step_get_dependencies.sh. package needs $PREFIX/include/linux/soundcard.h
		BLACKLIST+=("inkscape")
		BLACKLIST+=("iptables")
		BLACKLIST+=("kf6-karchive")
		BLACKLIST+=("kf6-kauth")
		BLACKLIST+=("kf6-kcodecs")
		BLACKLIST+=("kf6-kconfig")
		BLACKLIST+=("kf6-kcoreaddons")
		BLACKLIST+=("kf6-kguiaddons")
		BLACKLIST+=("kf6-ki18n")
		BLACKLIST+=("kf6-kitemmodels")
		BLACKLIST+=("kf6-kitemviews")
		BLACKLIST+=("kf6-kwidgetsaddons")
		BLACKLIST+=("kf6-kwindowsystem")
		BLACKLIST+=("layer-shell-qt")
		BLACKLIST+=("ldc")
		BLACKLIST+=("lenmus")
		BLACKLIST+=("lfortran")
		BLACKLIST+=("lgogdownloader")
		BLACKLIST+=("libdbusmenu-lxqt")
		BLACKLIST+=("libfm-qt")
		BLACKLIST+=("libgnustep-base")
		BLACKLIST+=("libhtmlcxx")
		BLACKLIST+=("liblightning")
		BLACKLIST+=("liblxqt")
		BLACKLIST+=("libmdbx")
		BLACKLIST+=("libmpeg2") # libandroid_shmget
		BLACKLIST+=("libportal")
		BLACKLIST+=("libqtxdg")
		BLACKLIST+=("librocksdb") # conflict gtest
		BLACKLIST+=("libsysstat")
		BLACKLIST+=("libtorrent") # ERROR: ./lib/libtorrent.so contains undefined symbols:    49: 0000000000000000     0 NOTYPE  GLOBAL DEFAULT   UND backtrace    50: 0000000000000000     0 NOTYPE  GLOBAL DEFAULT   UND backtrace_symbols
		BLACKLIST+=("libvncserver")
		BLACKLIST+=("libxmlrpc")
		BLACKLIST+=("lighttpd")
		BLACKLIST+=("lit")
		BLACKLIST+=("lite-xl")
		BLACKLIST+=("luvi")
		BLACKLIST+=("luvit")
		BLACKLIST+=("lximage-qt")
		BLACKLIST+=("lxqt-about")
		BLACKLIST+=("lxqt-archiver")
		BLACKLIST+=("lxqt-build-tools-qt5")
		BLACKLIST+=("lxqt-config")
		BLACKLIST+=("lxqt-globalkeys")
		BLACKLIST+=("lxqt-menu-data")
		BLACKLIST+=("lxqt-notificationd")
		BLACKLIST+=("lxqt-openssh-askpass")
		BLACKLIST+=("lxqt-panel")
		BLACKLIST+=("lxqt-qtplugin")
		BLACKLIST+=("lxqt-runner")
		BLACKLIST+=("lxqt-session")
		BLACKLIST+=("manim")
		BLACKLIST+=("mapserver") # gdal
		BLACKLIST+=("mariadb")
		BLACKLIST+=("matplotlib") # numpy
		BLACKLIST+=("mdbook-linkcheck")
		BLACKLIST+=("mgba")
		BLACKLIST+=("mindforger")
		BLACKLIST+=("mkvtoolnix")
		BLACKLIST+=("mpv-x")
		BLACKLIST+=("mu") # emacs
		BLACKLIST+=("mumble-server")
		BLACKLIST+=("music-file-organizer")
		BLACKLIST+=("ncpamixer")
		BLACKLIST+=("net-snmp")
		BLACKLIST+=("nextcloud-client")
		BLACKLIST+=("ntfs-3g")
		BLACKLIST+=("obconf-qt")
		BLACKLIST+=("octave-x")
		BLACKLIST+=("octave")
		BLACKLIST+=("openethereum")
		BLACKLIST+=("pass-otp")
		BLACKLIST+=("pass")
		BLACKLIST+=("peaclock")
		BLACKLIST+=("pika") # gtest
		BLACKLIST+=("pipewire") # opaque pointers
		BLACKLIST+=("poac") # opaque pointers
		BLACKLIST+=("postgis")
		BLACKLIST+=("predict")
		BLACKLIST+=("pv")
		BLACKLIST+=("pypy")
		BLACKLIST+=("pypy3")
		BLACKLIST+=("pyqt5")
		BLACKLIST+=("python-contourpy")
		BLACKLIST+=("python-grpcio")
		BLACKLIST+=("python-msgpack") # conflict libmsgpack
		BLACKLIST+=("python-numpy")
		BLACKLIST+=("python-onnxruntime")
		BLACKLIST+=("python-pyarrow")
		BLACKLIST+=("python-pynvim") # conflict libmsgpack
		BLACKLIST+=("python-scipy") # numpy
		BLACKLIST+=("qt5-qmake")
		BLACKLIST+=("qt5-qtbase")
		BLACKLIST+=("qt5-qtdeclarative")
		BLACKLIST+=("qt5-qtgraphicaleffects")
		BLACKLIST+=("qt5-qtlocation")
		BLACKLIST+=("qt5-qtmultimedia")
		BLACKLIST+=("qt5-qtquickcontrols")
		BLACKLIST+=("qt5-qtquickcontrols2")
		BLACKLIST+=("qt5-qtscript")
		BLACKLIST+=("qt5-qtsensors")
		BLACKLIST+=("qt5-qtserialport")
		BLACKLIST+=("qt5-qtsvg")
		BLACKLIST+=("qt5-qttools")
		BLACKLIST+=("qt5-qtwebchannel")
		BLACKLIST+=("qt5-qtwebengine")
		BLACKLIST+=("qt5-qtwebkit")
		BLACKLIST+=("qt5-qtwebsockets")
		BLACKLIST+=("qt5-qtx11extras")
		BLACKLIST+=("qt5-qtxmlpatterns")
		BLACKLIST+=("qt5ct")
		BLACKLIST+=("qt6-qtbase")
		BLACKLIST+=("qt6-qtcharts")
		BLACKLIST+=("qt6-qtdeclarative")
		BLACKLIST+=("qt6-qtimageformats")
		BLACKLIST+=("qt6-qtlanguageserver")
		BLACKLIST+=("qt6-qtmultimedia")
		BLACKLIST+=("qt6-qtsvg")
		BLACKLIST+=("qt6-qttools")
		BLACKLIST+=("qt6-qttranslations")
		BLACKLIST+=("qt6-qtwayland")
		BLACKLIST+=("qt6-shadertools")
		BLACKLIST+=("qt6ct")
		BLACKLIST+=("quick-lint-js") # conflict gtest
		BLACKLIST+=("recutils")
		BLACKLIST+=("redis")  # opaque pointers
		BLACKLIST+=("remind")
		BLACKLIST+=("rirc") # opaque pointers
		BLACKLIST+=("rizin")
		BLACKLIST+=("rpm")
		BLACKLIST+=("rsnapshot")
		BLACKLIST+=("rtorrent")
		BLACKLIST+=("shellcheck") # ghc-libs
		BLACKLIST+=("simulavr")
		BLACKLIST+=("smalltalk")
		BLACKLIST+=("snmptt")
		BLACKLIST+=("squashfuse")
		BLACKLIST+=("swift")
		BLACKLIST+=("tinygo")
		BLACKLIST+=("toxic")
		BLACKLIST+=("tvheadend")
		BLACKLIST+=("unar")
		BLACKLIST+=("valgrind")
		BLACKLIST+=("vlc") # libmpeg2
		BLACKLIST+=("waypipe")
		BLACKLIST+=("z3")
		BLACKLIST+=("olivia")
		BLACKLIST+=("opencv")
		BLACKLIST+=("oshu")
		BLACKLIST+=("otter-browser")
		BLACKLIST+=("pavucontrol-qt")
		BLACKLIST+=("pcmanfm-qt")
		BLACKLIST+=("phantomjs")
		BLACKLIST+=("python-pyqtwebengine")
		BLACKLIST+=("python-qscintilla")
		BLACKLIST+=("python-torch")
		BLACKLIST+=("python-torchaudio")
		BLACKLIST+=("python-torchvision")
		BLACKLIST+=("qemu-system-x86-64")
		BLACKLIST+=("qterminal")
		BLACKLIST+=("qtermwidget")
		BLACKLIST+=("qtxdg-tools")
		BLACKLIST+=("quassel")
		BLACKLIST+=("schismtracker")
		BLACKLIST+=("scrcpy")
		BLACKLIST+=("sdl2-image")
		BLACKLIST+=("sdl2-gfx")
		BLACKLIST+=("sdl2-net")
		BLACKLIST+=("sdl2-mixer")
		BLACKLIST+=("sdl2-pango")
		BLACKLIST+=("sdl2-ttf")
		BLACKLIST+=("sway")
		BLACKLIST+=("the-powder-toy")
		BLACKLIST+=("tigervnc")
		BLACKLIST+=("trojita")
		BLACKLIST+=("tuxpaint")
		BLACKLIST+=("vlc-qt")
		BLACKLIST+=("wayvnc")
		BLACKLIST+=("wine-stable")
		BLACKLIST+=("wkhtmltopdf")
		BLACKLIST+=("wlroots")
		BLACKLIST+=("x11vnc")
		BLACKLIST+=("xf86-input-void")
		BLACKLIST+=("xf86-video-dummy")
		BLACKLIST+=("xorg-server")
		BLACKLIST+=("xorg-server-xvfb") # /home/builder/.termux-build/xorg-server-xvfb/src/mi/mi.h:153:10: error: unknown type name 'DrawablePtr'; did you mean 'Drawable'?
		BLACKLIST+=("xpdf")
		BLACKLIST+=("xrdp")
		BLACKLIST+=("xwayland")


		for add_pkg in $(ls $TERMUX_PACKAGES_DIRECTORY/packages && \
		                 ls $TERMUX_PACKAGES_DIRECTORY/root-packages && \
		 				 ls $TERMUX_PACKAGES_DIRECTORY/x11-packages); do
			if [[ " ${PACKAGES[*]} " != *" $add_pkg "* ]] && \
			   [[ " ${BLACKLIST[*]} " != *" $add_pkg "* ]]; then
				PACKAGES+=("$add_pkg")
			fi
		done
		unset add_pkg

		# Build packages.
		for package_name in "${PACKAGES[@]}"; do
			set +e
			build_package "$package_arch" "$package_name" || return $?
			set -e
		done

		# Extract all debs.
		extract_debs || return $?

		# Add termux bootstrap second stage files
		add_termux_bootstrap_second_stage_files "$package_arch"

		# Create bootstrap archive.
		create_bootstrap_archive "$package_arch" || return $?

	done

}

main "$@"
