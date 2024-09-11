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

# A list of non-essential packages to build.
# By default it is empty, but can be filled with option '--add'.
declare -a ADDITIONAL_PACKAGES=()

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


	if [ ! -d $TERMUX_PACKAGES_DIRECTORY/*packages/$package_name ]; then
		local dir_subpackage=$(ls $TERMUX_PACKAGES_DIRECTORY/*packages/*/$package_name.subpackage.sh)
		dir_subpackage=(${dir_subpackage//// })
		package_name="${dir_subpackage[-2]}"
	fi

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

		if ! grep -x "$current_package_name" "$TERMUX_PACKAGES_DIRECTORY/bootstrap_package_names.txt"; then
			echo "[*] Skipping unnecessary package '$deb'..."
			continue
		fi

		if [[ "$current_package_name" == *"-static" ]]; then
			echo "[*] Skipping static package '$deb'..."
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
  [ -a | --add <packages> ]
                     Additional packages to include into bootstrap archive.
                     Multiple packages should be passed as comma-separated list.
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

Build bootstrap archive with additionall openssh package for aarch64 arch only:
./scripts/run-docker.sh ./scripts/build-bootstraps.sh --architectures aarch64 --add openssh &> build.log
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
			-a|--add)
				if [ $# -gt 1 ] && [ -n "$2" ] && [[ $2 != -* ]]; then
					for pkg in $(echo "$2" | tr ',' ' '); do
						ADDITIONAL_PACKAGES+=("$pkg")
					done
					unset pkg
					shift 1
				else
					echo "[!] Option '--add' requires an argument." 1>&2
					show_usage
					return 1
				fi
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

		# PACKAGES+=("abseil-cpp")
		# PACKAGES+=("adwaita-icon-theme-legacy")
		# PACKAGES+=("adwaita-icon-theme")
		# PACKAGES+=("alsa-lib")
		# PACKAGES+=("android-tools")
		# PACKAGES+=("angle-android")
		# PACKAGES+=("apache2")
		# PACKAGES+=("glib-bin")
		# PACKAGES+=("glib-networking")
		# PACKAGES+=("glib")
		# PACKAGES+=("appstream")
		# PACKAGES+=("apr-util")
		# PACKAGES+=("apr")
		# PACKAGES+=("apt")
		# PACKAGES+=("arj")
		# PACKAGES+=("aspell")
		# PACKAGES+=("at-spi2-core")
		# PACKAGES+=("atk")
		# PACKAGES+=("attr")
		# PACKAGES+=("autoconf")
		# PACKAGES+=("automake")
		# PACKAGES+=("bash")
		# PACKAGES+=("bat")
		# PACKAGES+=("bc")
		# PACKAGES+=("binutils-bin")
		# PACKAGES+=("binutils-libs")
		# PACKAGES+=("binutils")
		# PACKAGES+=("bison")
		# PACKAGES+=("brotli")
		# PACKAGES+=("bsdtar")
		# PACKAGES+=("build-essential")
		# PACKAGES+=("bzip2")
		# PACKAGES+=("c-ares")
		# PACKAGES+=("ca-certificates-java")
		# PACKAGES+=("ca-certificates")
		# PACKAGES+=("cargo-c")
		# PACKAGES+=("clang")
		# PACKAGES+=("cloudflared")
		# PACKAGES+=("cmake")
		# PACKAGES+=("command-not-found")
		# PACKAGES+=("coreutils")
		# PACKAGES+=("cpio")
		# PACKAGES+=("curl")
		# PACKAGES+=("dash")
		# PACKAGES+=("dbus")
		# PACKAGES+=("dconf")
		# PACKAGES+=("debianutils")
		# PACKAGES+=("desktop-file-utils")
		# PACKAGES+=("dialog")
		# PACKAGES+=("diffutils")
		# PACKAGES+=("dos2unix")
		# PACKAGES+=("double-conversion")
		# PACKAGES+=("dpkg")
		# PACKAGES+=("ed")
		# PACKAGES+=("enchant")
		# PACKAGES+=("exo")
		# PACKAGES+=("ffmpeg")
		# PACKAGES+=("fftw")
		# PACKAGES+=("file-roller-help")
		# PACKAGES+=("file-roller")
		# PACKAGES+=("findutils")
		# PACKAGES+=("firefox")
		# PACKAGES+=("flex")
		# PACKAGES+=("fluidsynth")
		# PACKAGES+=("fontconfig")
		# PACKAGES+=("freetype")
		# PACKAGES+=("fribidi")
		# PACKAGES+=("game-music-emu")
		# PACKAGES+=("garcon")
		# PACKAGES+=("gawk")
		# PACKAGES+=("gcr")
		# PACKAGES+=("gdbm")
		# PACKAGES+=("gdk-pixbuf")
		# PACKAGES+=("getconf")
		# PACKAGES+=("gh")
		# PACKAGES+=("giflib")
		# PACKAGES+=("git")
		# PACKAGES+=("glow")
		# PACKAGES+=("gnupg")
		# PACKAGES+=("golang")
		# PACKAGES+=("gperf")
		# PACKAGES+=("gpgme")
		# PACKAGES+=("gpgmepp")
		# PACKAGES+=("gpgv")
		# PACKAGES+=("graphene")
		# PACKAGES+=("grep")
		# PACKAGES+=("gsettings-desktop-schemas")
		# PACKAGES+=("gst-plugins-bad")
		# PACKAGES+=("gst-plugins-base")
		# PACKAGES+=("gst-plugins-good")
		# PACKAGES+=("gstreamer")
		# PACKAGES+=("gtk-update-icon-cache")
		# PACKAGES+=("gtk3")
		# PACKAGES+=("gtk4")
		# PACKAGES+=("gvfs")
		# PACKAGES+=("gzip")
		# PACKAGES+=("harfbuzz-icu")
		# PACKAGES+=("harfbuzz")
		# PACKAGES+=("hicolor-icon-theme")
		# PACKAGES+=("html2text")
		# PACKAGES+=("hunspell-en-us")
		# PACKAGES+=("hunspell")
		# PACKAGES+=("imagemagick")
		# PACKAGES+=("imath")
		# PACKAGES+=("imlib2")
		# PACKAGES+=("inetutils")
		# PACKAGES+=("iso-codes")
		# PACKAGES+=("jack2")
		# PACKAGES+=("jack")
		# PACKAGES+=("jq")
		# PACKAGES+=("json-glib")
		# PACKAGES+=("jsoncpp")
		# PACKAGES+=("krb5")
		# PACKAGES+=("ldns")
		# PACKAGES+=("less")
		# PACKAGES+=("libadwaita")
		# PACKAGES+=("libandroid-execinfo")
		# PACKAGES+=("libandroid-glob")
		# PACKAGES+=("libandroid-posix-semaphore")
		# PACKAGES+=("libandroid-shmem")
		# PACKAGES+=("libandroid-spawn")
		# PACKAGES+=("libandroid-support")
		# PACKAGES+=("libandroid-sysv-semaphore")
		# PACKAGES+=("libandroid-utimes")
		# PACKAGES+=("libaom")
		# PACKAGES+=("libarchive")
		# PACKAGES+=("libarrow-cpp")
		# PACKAGES+=("libass")
		# PACKAGES+=("libassuan")
		# PACKAGES+=("libbluray")
		# PACKAGES+=("libbz2")
		# PACKAGES+=("libc++")
		# PACKAGES+=("libcaca")
		# PACKAGES+=("libcairo")
		# PACKAGES+=("libcanberra")
		# PACKAGES+=("libcap-ng")
		# PACKAGES+=("libcap")
		# PACKAGES+=("libcompiler-rt")
		# PACKAGES+=("libcrypt")
		# PACKAGES+=("libcurl")
		# PACKAGES+=("libdav1d")
		# PACKAGES+=("libdb")
		# PACKAGES+=("libde265")
		# PACKAGES+=("libdecor")
		# PACKAGES+=("libdrm")
		# PACKAGES+=("libedit")
		# PACKAGES+=("libepoxy")
		# PACKAGES+=("libevent")
		# PACKAGES+=("libexif")
		# PACKAGES+=("libexpat")
		# PACKAGES+=("libffi")
		# PACKAGES+=("libflac")
		# PACKAGES+=("libgcrypt")
		# PACKAGES+=("libgd")
		# PACKAGES+=("libgit2")
		# PACKAGES+=("libglvnd-dev")
		# PACKAGES+=("libglvnd")
		# PACKAGES+=("libgmp")
		# PACKAGES+=("libgnutls")
		# PACKAGES+=("libgpg-error")
		# PACKAGES+=("libgraphite")
		# PACKAGES+=("libgtop")
		# PACKAGES+=("libheif")
		# PACKAGES+=("libhyphen")
		# PACKAGES+=("libice")
		# PACKAGES+=("libiconv")
		# PACKAGES+=("libicu")
		# PACKAGES+=("libid3tag")
		# PACKAGES+=("libidn2")
		# PACKAGES+=("libimagequant")
		# PACKAGES+=("libjpeg-turbo-progs")
		# PACKAGES+=("libjpeg-turbo-static")
		# PACKAGES+=("libjpeg-turbo")
		# PACKAGES+=("libjxl")
		# PACKAGES+=("libksba")
		# PACKAGES+=("libllvm")
		# PACKAGES+=("libltdl")
		# PACKAGES+=("liblua51")
		# PACKAGES+=("liblua52")
		# PACKAGES+=("libluajit")
		# PACKAGES+=("liblz4")
		# PACKAGES+=("liblzma")
		# PACKAGES+=("liblzo")
		# PACKAGES+=("libmd")
		# PACKAGES+=("libmodplug")
		# PACKAGES+=("libmp3lame")
		# PACKAGES+=("libmpfr")
		# PACKAGES+=("libmsgpack")
		# PACKAGES+=("libnettle")
		# PACKAGES+=("libnghttp2")
		# PACKAGES+=("libnghttp3")
		# PACKAGES+=("libnotify")
		# PACKAGES+=("libnpth")
		# PACKAGES+=("libnspr")
		# PACKAGES+=("libnss")
		# PACKAGES+=("libogg")
		# PACKAGES+=("libopenblas")
		# PACKAGES+=("libopencore-amr")
		# PACKAGES+=("libopenmpt")
		# PACKAGES+=("libopus")
		# PACKAGES+=("libpipeline")
		# PACKAGES+=("libpixman")
		# PACKAGES+=("libplacebo")
		# PACKAGES+=("libplist-static")
		# PACKAGES+=("libplist")
		# PACKAGES+=("libpng")
		# PACKAGES+=("libprotobuf")
		# PACKAGES+=("libpsl")
		# PACKAGES+=("libraqm")
		# PACKAGES+=("librav1e")
		# PACKAGES+=("libre2")
		# PACKAGES+=("libresolv-wrapper")
		# PACKAGES+=("librsvg")
		# PACKAGES+=("libsamplerate")
		# PACKAGES+=("libsasl")
		# PACKAGES+=("libsass")
		# PACKAGES+=("libsixel")
		# PACKAGES+=("libsm")
		# PACKAGES+=("libsmartcols")
		# PACKAGES+=("libsnappy")
		# PACKAGES+=("libsndfile")
		# PACKAGES+=("libsoup3")
		# PACKAGES+=("libsoxr")
		# PACKAGES+=("libsqlite")
		# PACKAGES+=("libsrt")
		# PACKAGES+=("libssh2")
		# PACKAGES+=("libssh")
		# PACKAGES+=("libstemmer")
		# PACKAGES+=("libtalloc")
		# PACKAGES+=("libtasn1")
		# PACKAGES+=("libtheora")
		# PACKAGES+=("libtiff")
		# PACKAGES+=("libtirpc")
		# PACKAGES+=("libtool")
		# PACKAGES+=("libtreesitter")
		# PACKAGES+=("libuchardet")
		# PACKAGES+=("libudfread")
		# PACKAGES+=("libunbound")
		# PACKAGES+=("libunibilium")
		# PACKAGES+=("libunistring")
		# PACKAGES+=("libusb")
		# PACKAGES+=("libuuid")
		# PACKAGES+=("libuv")
		# PACKAGES+=("libv4l")
		# PACKAGES+=("libvidstab")
		# PACKAGES+=("libvo-amrwbenc")
		# PACKAGES+=("libvorbis")
		# PACKAGES+=("libvpx")
		# PACKAGES+=("libvte")
		# PACKAGES+=("libvterm")
		# PACKAGES+=("libwayland")
		# PACKAGES+=("libwebp")
		# PACKAGES+=("libwebrtc-audio-processing")
		# PACKAGES+=("libwnck")
		# PACKAGES+=("libx11")
		# PACKAGES+=("libx264")
		# PACKAGES+=("libx265")
		# PACKAGES+=("libxau")
		# PACKAGES+=("libxcb")
		# PACKAGES+=("libxcomposite")
		# PACKAGES+=("libxcursor")
		# PACKAGES+=("libxdamage")
		# PACKAGES+=("libxdmcp")
		# PACKAGES+=("libxext")
		# PACKAGES+=("libxfce4ui")
		# PACKAGES+=("libxfce4util")
		# PACKAGES+=("libxfixes")
		# PACKAGES+=("libxft")
		# PACKAGES+=("libxi")
		# PACKAGES+=("libxinerama")
		# PACKAGES+=("libxkbcommon")
		# PACKAGES+=("libxkbfile")
		# PACKAGES+=("libxklavier")
		# PACKAGES+=("libxml2")
		# PACKAGES+=("libxmlb")
		# PACKAGES+=("libxmu")
		# PACKAGES+=("libxrandr")
		# PACKAGES+=("libxrender")
		# PACKAGES+=("libxshmfence")
		# PACKAGES+=("libxslt")
		# PACKAGES+=("libxss")
		# PACKAGES+=("libxt")
		# PACKAGES+=("libxtst")
		# PACKAGES+=("libxv")
		# PACKAGES+=("libxxf86vm")
		# PACKAGES+=("libyaml-cpp")
		# PACKAGES+=("libyaml")
		# PACKAGES+=("libzimg")
		# PACKAGES+=("libzip")
		# PACKAGES+=("littlecms")
		# PACKAGES+=("lld")
		# PACKAGES+=("llvm")
		# PACKAGES+=("lsd")
		# PACKAGES+=("lsof")
		# PACKAGES+=("lua-language-server")
		# PACKAGES+=("lua51-lpeg")
		# PACKAGES+=("luv")
		# PACKAGES+=("lxde-icon-theme")
		# PACKAGES+=("lz4")
		# PACKAGES+=("lzip")
		# PACKAGES+=("lzop")
		# PACKAGES+=("m4")
		# PACKAGES+=("make")
		# PACKAGES+=("mesa")
		# PACKAGES+=("mongodb")
		# PACKAGES+=("mpg123")
		# PACKAGES+=("python-pip") # python-pip must be in this specific build list before mpv to prevent "ERROR: Package python-pip doesn't build properly."
		# PACKAGES+=("mpv")
		# PACKAGES+=("mtdev")
		# PACKAGES+=("nano")
		# PACKAGES+=("ncurses-ui-libs")
		# PACKAGES+=("ncurses-utils")
		# PACKAGES+=("ncurses")
		# PACKAGES+=("ndk-sysroot")
		# PACKAGES+=("neofetch")
		# PACKAGES+=("neovim")
		# PACKAGES+=("net-tools")
		# PACKAGES+=("ninja")
		# PACKAGES+=("nmh")
		# PACKAGES+=("nodejs")
		# PACKAGES+=("ocl-icd")
		# PACKAGES+=("oniguruma")
		# PACKAGES+=("openal-soft")
		# PACKAGES+=("openexr")
		# PACKAGES+=("opengl")
		# # PACKAGES+=("openjdk-17-x")
		# PACKAGES+=("openjdk-17")
		# PACKAGES+=("openjpeg")
		# PACKAGES+=("openssh-sftp-server")
		# PACKAGES+=("openssh")
		# PACKAGES+=("openssl")
		# PACKAGES+=("opusfile")
		# PACKAGES+=("p11-kit")
		# PACKAGES+=("p7zip")
		# PACKAGES+=("pango")
		# PACKAGES+=("patch")
		# PACKAGES+=("patchelf")
		# PACKAGES+=("pcre2")
		# PACKAGES+=("pcre")
		# PACKAGES+=("perl")
		# PACKAGES+=("php")
		# PACKAGES+=("pinentry")
		# PACKAGES+=("pkg-config")
		# PACKAGES+=("poppler-data")
		# PACKAGES+=("poppler")
		# PACKAGES+=("postgresql")
		# PACKAGES+=("procps")
		# PACKAGES+=("proot-distro")
		# PACKAGES+=("proot")
		# PACKAGES+=("psmisc")
		# PACKAGES+=("pulseaudio")
		# PACKAGES+=("python-apt")
		# PACKAGES+=("python-brotli")
		# PACKAGES+=("python-cryptography")
		# PACKAGES+=("python-ensurepip-wheels")
		# PACKAGES+=("python-kivy")
		# PACKAGES+=("python-libsass")
		# PACKAGES+=("python-numpy-static")
		# PACKAGES+=("python-numpy")
		# # PACKAGES+=("python-pandas")
		# PACKAGES+=("python-pillow")
		# PACKAGES+=("python-pycryptodomex")
		# PACKAGES+=("python-static")
		# PACKAGES+=("python-tiktoken")
		# PACKAGES+=("python")
		# PACKAGES+=("qt5-qtbase")
		# PACKAGES+=("qt5-qtdeclarative")
		# PACKAGES+=("qt5-qtlocation")
		# PACKAGES+=("qt5-qtmultimedia")
		# PACKAGES+=("qt5-qtsensors")
		# PACKAGES+=("qt5-qtsvg")
		# # PACKAGES+=("qt5-qtwebkit")
		# PACKAGES+=("qt5-qtxmlpatterns")
		# PACKAGES+=("readline")
		# PACKAGES+=("resolv-conf")
		# PACKAGES+=("rhash")
		# PACKAGES+=("ripgrep")
		# PACKAGES+=("rlwrap")
		# PACKAGES+=("root-repo")
		# PACKAGES+=("rubberband")
		# PACKAGES+=("ruby")
		# PACKAGES+=("ruff")
		# # PACKAGES+=("rust-std-aarch64-linux-android")
		# PACKAGES+=("rust")
		# PACKAGES+=("sdl2-image")
		# PACKAGES+=("sdl2-mixer")
		# PACKAGES+=("sdl2-ttf")
		# PACKAGES+=("sdl2")
		# PACKAGES+=("sed")
		# PACKAGES+=("shared-mime-info")
		# PACKAGES+=("speexdsp")
		# PACKAGES+=("sqlite")
		# PACKAGES+=("startup-notification")
		# PACKAGES+=("stylua")
		# PACKAGES+=("svt-av1")
		# PACKAGES+=("tar")
		# PACKAGES+=("termimage")
		# PACKAGES+=("termux-am-socket")
		# PACKAGES+=("termux-am")
		# PACKAGES+=("termux-auth")
		# PACKAGES+=("termux-exec")
		# PACKAGES+=("termux-keyring")
		# PACKAGES+=("termux-licenses")
		# PACKAGES+=("termux-tools")
		# PACKAGES+=("termux-x11-nightly")
		# PACKAGES+=("thrift")
		# PACKAGES+=("thunar-archive-plugin")
		# PACKAGES+=("thunar")
		# PACKAGES+=("tidy")
		# PACKAGES+=("tmate")
		# PACKAGES+=("tmux")
		# PACKAGES+=("translate-shell")
		# PACKAGES+=("tree-sitter-lua")
		# PACKAGES+=("tree-sitter-query")
		# PACKAGES+=("tree-sitter-vimdoc")
		# PACKAGES+=("tree")
		# PACKAGES+=("ttf-dejavu")
		# PACKAGES+=("tumbler")
		# PACKAGES+=("tur-repo")
		# PACKAGES+=("unrar")
		# PACKAGES+=("unzip")
		# PACKAGES+=("utf8proc")
		# PACKAGES+=("util-linux")
		# PACKAGES+=("vim-runtime")
		# PACKAGES+=("vim")
		# PACKAGES+=("virglrenderer-android")
		# PACKAGES+=("vulkan-loader-generic")
		# PACKAGES+=("vulkan-loader")
		# PACKAGES+=("webkit2gtk-4.1")
		# PACKAGES+=("wget")
		# PACKAGES+=("wkhtmltopdf")
		# PACKAGES+=("woff2")
		# PACKAGES+=("x11-repo")
		# PACKAGES+=("xcb-util-image")
		# PACKAGES+=("xcb-util-keysyms")
		# PACKAGES+=("xcb-util-renderutil")
		# PACKAGES+=("xcb-util-wm")
		# PACKAGES+=("xcb-util")
		# PACKAGES+=("xfce4-notifyd")
		# PACKAGES+=("xfce4-panel")
		# PACKAGES+=("xfce4-session")
		# PACKAGES+=("xfce4-settings")
		# PACKAGES+=("xfce4-terminal")
		# PACKAGES+=("xfce4")
		# PACKAGES+=("xfconf")
		# PACKAGES+=("xfdesktop")
		# PACKAGES+=("xfwm4")
		# PACKAGES+=("xkeyboard-config")
		# PACKAGES+=("xorg-iceauth")
		# PACKAGES+=("xorg-xkbcomp")
		# PACKAGES+=("xorg-xrdb")
		# PACKAGES+=("xvidcore")
		# PACKAGES+=("xxhash")
		# PACKAGES+=("xz-utils")
		# PACKAGES+=("zenity")
		# PACKAGES+=("zip")
		# PACKAGES+=("zlib")
		# PACKAGES+=("zsh-completions")
		# PACKAGES+=("zsh")
		# PACKAGES+=("zstd")

		# PACKAGES+=("bash-completion")

		# Handle additional packages.
		for add_pkg in "${ADDITIONAL_PACKAGES[@]}"; do
			if [[ " ${PACKAGES[*]} " != *" $add_pkg "* ]]; then
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
