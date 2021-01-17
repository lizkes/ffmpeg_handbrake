#!/bin/bash

# HOMEPAGE: https://github.com/markus-perl/ffmpeg-build-script
# LICENSE: https://github.com/markus-perl/ffmpeg-build-script/blob/master/LICENSE

PROGNAME=$(basename "$0")
VERSION=1.21
CWD=$(pwd)
PACKAGES="$CWD/packages"
WORKSPACE="$CWD/workspace"
CFLAGS="-I$WORKSPACE/include"
LDFLAGS="-L$WORKSPACE/lib"
LDEXEFLAGS=""
EXTRALIBS="-ldl -lpthread -lm -lz"
CONFIGURE_OPTIONS=()

# Speed up the process
# Env Var NUMJOBS overrides automatic detection
if [[ -n "$NUMJOBS" ]]; then
	MJOBS="$NUMJOBS"
elif [[ -f /proc/cpuinfo ]]; then
	MJOBS=$(grep -c processor /proc/cpuinfo)
elif [[ "$OSTYPE" == "darwin"* ]]; then
	MJOBS=$(sysctl -n machdep.cpu.thread_count)
	CONFIGURE_OPTIONS=("--enable-videotoolbox")
else
	MJOBS=4
fi

make_dir () {
	remove_dir "$1"
	if ! mkdir "$1"; then
		printf "\n Failed to create dir %s" "$1";
		exit 1
	fi
}

remove_dir () {
	if [ -d "$1" ]; then
		rm -r "$1"
	fi
}

download () {
	# download url [filename[dirname]]

	DOWNLOAD_PATH="$PACKAGES"
	DOWNLOAD_FILE="${2:-"${1##*/}"}"

	if [[ "$DOWNLOAD_FILE" =~ "tar." ]]; then
		TARGETDIR="${DOWNLOAD_FILE%.*}"
		TARGETDIR="${3:-"${TARGETDIR%.*}"}"
	else
		TARGETDIR="${3:-"${DOWNLOAD_FILE%.*}"}"
	fi

	if [ ! -f "$DOWNLOAD_PATH/$DOWNLOAD_FILE" ]; then
		echo "Downloading $1 as $DOWNLOAD_FILE"
		curl -L --silent -o "$DOWNLOAD_PATH/$DOWNLOAD_FILE" "$1"

		EXITCODE=$?
		if [ $EXITCODE -ne 0 ]; then
			echo ""
			echo "Failed to download $1. Exitcode $EXITCODE. Retrying in 10 seconds";
			sleep 10
			curl -L --silent -o "$DOWNLOAD_PATH/$DOWNLOAD_FILE" "$1"
		fi

		EXITCODE=$?
		if [ $EXITCODE -ne 0 ]; then
			echo ""
			echo "Failed to download $1. Exitcode $EXITCODE";
			exit 1
		fi

		echo "... Done"
	else
		echo "$DOWNLOAD_FILE has already downloaded."
	fi

	make_dir "$DOWNLOAD_PATH/$TARGETDIR"

	if [ -n "$3" ]; then
		if ! tar -xvf "$DOWNLOAD_PATH/$DOWNLOAD_FILE" -C "$DOWNLOAD_PATH/$TARGETDIR" 2>/dev/null >/dev/null; then
			echo "Failed to extract $DOWNLOAD_FILE";
			exit 1
		fi
	else
		if ! tar -xvf "$DOWNLOAD_PATH/$DOWNLOAD_FILE" -C "$DOWNLOAD_PATH/$TARGETDIR" --strip-components 1 2>/dev/null >/dev/null; then
			echo "Failed to extract $DOWNLOAD_FILE";
			exit 1
		fi
	fi

	echo "Extracted $DOWNLOAD_FILE";

	cd "$DOWNLOAD_PATH/$TARGETDIR" || (echo "Error has occurred." ; exit 1)
}

execute () {
	echo "$ $*"

	OUTPUT=$("$@" 2>&1)

	# shellcheck disable=SC2181
	if [ $? -ne 0 ]; then
		echo "$OUTPUT"
		echo ""
		echo "Failed to Execute $*" >&2
		exit 1
	fi
}

build () {
	echo ""
	echo "building $1"
	echo "======================="

	if [ -f "$PACKAGES/$1.done" ]; then
		echo "$1 already built. Remove $PACKAGES/$1.done lockfile to rebuild it."
		return 1
	fi

	return 0
}

command_exists () {
	if ! [[ -x $(command -v "$1") ]]; then
		return 1
	fi

	return 0
}

library_exists () {
	local result=0
	local output=$(pkg-config --exists --print-errors "$1" 2>&1 > /dev/null) || result=$?
	if [ ! "$result" = "0" ]; then
		return 1
	fi

	return 0
}

build_done () {
	touch "$PACKAGES/$1.done"
}

cleanup () {
	remove_dir "$PACKAGES"
	remove_dir "$WORKSPACE"
	echo "Cleanup done."
	echo ""
}

usage () {
	echo "Usage: $PROGNAME [OPTIONS]"
	echo "Options:"
	echo "  -h, --help          Display usage information"
	echo "      --version       Display version information"
	echo "  -b, --build         Starts the build process"
	echo "  -c, --cleanup       Remove all working dirs"
	echo "  -f, --full-static   Build a full static FFmpeg binary (eg. glibc, pthreads etc...) **only Linux**"
	echo "                      Note: Because of the NSS (Name Service Switch), glibc does not recommend static links."
	echo ""
}

while (( $# > 0 )); do
	case $1 in
		-h | --help)
			usage
			exit 0
			;;
		--version)
			echo "$VERSION"
			exit 0
			;;
		-*)
			if [[ "$1" == "--build" || "$1" =~ 'b' ]]; then
				bflag='-b'
			fi
			if [[ "$1" == "--cleanup" || "$1" =~ 'c'  && ! "$1" =~ '--' ]]; then
				cflag='-c'
				cleanup
			fi
			if [[ "$1" == "--full-static" || "$1" =~ 'f' ]]; then
				if [[ "$OSTYPE" == "darwin"* ]]; then
					echo "Error: A full static binary can only be build on Linux."
					exit 1
				fi
				LDEXEFLAGS="-static"
			fi
			shift
			;;
		*)
			usage
			exit 1
			;;
	esac
done

echo "ffmpeg-build-script v$VERSION"
echo "========================="
echo ""

if [ -z "$bflag" ]; then
	if [ -z "$cflag" ]; then
		usage
		exit 1
	fi
	exit 0
fi

echo "Using $MJOBS make jobs simultaneously."

if [ -n "$LDEXEFLAGS" ]; then
	echo "Start the build in full static mode."
fi

mkdir -p "$PACKAGES"
mkdir -p "$WORKSPACE"

export PATH="${WORKSPACE}/bin:$PATH"
PKG_CONFIG_PATH="/usr/local/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig"
PKG_CONFIG_PATH+=":/usr/local/share/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/lib64/pkgconfig"
export PKG_CONFIG_PATH

if ! command_exists "make"; then
	echo "make not installed.";
	exit 1
fi

if ! command_exists "g++"; then
	echo "g++ not installed.";
	exit 1
fi

if ! command_exists "curl"; then
	echo "curl not installed.";
	exit 1
fi

if ! command_exists "python"; then
	echo "Python command not found. Lv2 filter will not be available.";
fi


##
## build tools
##

if build "pkg-config"; then
	download "https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
	execute ./configure --silent --prefix="${WORKSPACE}" --with-pc-path="${WORKSPACE}"/lib/pkgconfig --with-internal-glib
	execute make -j $MJOBS
	execute make install
	build_done "pkg-config"
fi


if command_exists "python"; then

  if build "lv2"; then
    download "https://lv2plug.in/spec/lv2-1.18.0.tar.bz2" "lv2-1.18.0.tar.bz2"
    execute ./waf configure --prefix="${WORKSPACE}" --lv2-user
    execute ./waf
    execute ./waf install

    build_done "lv2"
  fi

  if build "waflib"; then
    download "https://gitlab.com/drobilla/autowaf/-/archive/cc37724b9bfa889baebd8cb10f38b8c7cab83e37/autowaf-cc37724b9bfa889baebd8cb10f38b8c7cab83e37.tar.gz" "autowaf.tar.gz"
    build_done "waflib"
  fi

  if build "serd"; then
    download "https://gitlab.com/drobilla/serd/-/archive/v0.30.6/serd-v0.30.6.tar.gz" "serd-v0.30.6.tar.gz"
    execute cp -r ${PACKAGES}/autowaf/* "${PACKAGES}/serd-v0.30.6/waflib/"
    execute ./waf configure --prefix="${WORKSPACE}" --static --no-shared --no-posix
    execute ./waf
    execute ./waf install
    build_done "serd"
  fi

  if build "pcre"; then
    download "https://ftp.pcre.org/pub/pcre/pcre-8.44.tar.gz" "pcre-8.44.tar.gz"
    execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
    execute make -j $MJOBS
    execute make install

    build_done "pcre"
  fi

  if build "sord"; then
    download "https://gitlab.com/drobilla/sord/-/archive/v0.16.6/sord-v0.16.6.tar.gz" "sord-v0.16.6.tar.gz"
    execute cp -r ${PACKAGES}/autowaf/* "${PACKAGES}/sord-v0.16.6/waflib/"
    execute ./waf configure --prefix="${WORKSPACE}" CFLAGS=${CFLAGS} --static --no-shared --no-utils
    execute ./waf CFLAGS=${CFLAGS}
    execute ./waf install

    build_done "sord"
  fi

  if build "sratom"; then
    download "https://gitlab.com/lv2/sratom/-/archive/v0.6.6/sratom-v0.6.6.tar.gz" "sratom-v0.6.6.tar.gz"
    execute cp -r ${PACKAGES}/autowaf/* "${PACKAGES}/sratom-v0.6.6/waflib/"
    execute ./waf configure --prefix="${WORKSPACE}" --static --no-shared
    execute ./waf
    execute ./waf install

    build_done "sratom"
  fi

  if build "lilv"; then
    download "https://gitlab.com/lv2/lilv/-/archive/v0.24.10/lilv-v0.24.10.tar.gz" "lilv-v0.24.10.tar.gz"
    execute cp -r ${PACKAGES}/autowaf/* "${PACKAGES}/lilv-v0.24.10/waflib/"
    execute ./waf configure --prefix="${WORKSPACE}" --static --no-shared --no-utils
    execute ./waf
    execute ./waf install
		CFLAGS+=" -I$WORKSPACE/include/lilv-0"
    build_done "lilv"
  fi

  CONFIGURE_OPTIONS+=("--enable-lv2")
fi

if build "yasm"; then
	download "https://github.com/yasm/yasm/releases/download/v1.3.0/yasm-1.3.0.tar.gz"
	execute ./configure --prefix="${WORKSPACE}"
	execute make -j $MJOBS
	execute make install
	build_done "yasm"
fi

if build "nasm"; then
	download "https://www.nasm.us/pub/nasm/releasebuilds/2.15.05/nasm-2.15.05.tar.xz"
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install
	build_done "nasm"
fi

if build "zlib"; then
	download "https://www.zlib.net/zlib-1.2.11.tar.gz"
	execute ./configure --static --prefix="${WORKSPACE}"
	execute make -j $MJOBS
	execute make install
	build_done "zlib"
fi

if build "openssl"; then
	download "https://www.openssl.org/source/openssl-1.1.1h.tar.gz"
	execute ./config --prefix="${WORKSPACE}" --openssldir="${WORKSPACE}" --with-zlib-include="${WORKSPACE}"/include/ --with-zlib-lib="${WORKSPACE}"/lib no-shared zlib
	execute make -j $MJOBS
	execute make install_sw

	build_done "openssl"
fi
CONFIGURE_OPTIONS+=("--enable-openssl")

if build "cmake"; then
	download "https://cmake.org/files/v3.18/cmake-3.18.4.tar.gz"
	execute ./configure --prefix="${WORKSPACE}" --system-zlib
	execute make -j $MJOBS
	execute make install
	build_done "cmake"
fi


##
## video library
##

if build "x264"; then
	download "https://code.videolan.org/videolan/x264/-/archive/stable/x264-stable.tar.bz2"

	if [[ "$OSTYPE" == "linux-gnu" ]]; then
		execute ./configure --prefix="${WORKSPACE}" --enable-static --enable-pic CXXFLAGS="-fPIC"
	else
		execute ./configure --prefix="${WORKSPACE}" --enable-static --enable-pic
	fi

	execute make -j $MJOBS
	execute make install
	execute make install-lib-static

	build_done "x264"
fi
CONFIGURE_OPTIONS+=("--enable-libx264")

if build "x265"; then
	download "https://github.com/videolan/x265/archive/Release_3.5.tar.gz" "x265-3.5.tar.gz"
	cd build/linux || exit
	execute cmake -DCMAKE_INSTALL_PREFIX="${WORKSPACE}" -DENABLE_SHARED=off -DBUILD_SHARED_LIBS=OFF ../../source
	execute make -j $MJOBS
	execute make install

	if [ -n "$LDEXEFLAGS" ]; then
		sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "${WORKSPACE}/lib/pkgconfig/x265.pc" # The -i.backup is intended and required on MacOS: https://stackoverflow.com/questions/5694228/sed-in-place-flag-that-works-both-on-mac-bsd-and-linux
	fi

	build_done "x265"
fi
CONFIGURE_OPTIONS+=("--enable-libx265")

if build "libvpx"; then
	download "https://github.com/webmproject/libvpx/archive/v1.9.0.tar.gz" "libvpx-1.9.0.tar.gz"

	if [[ "$OSTYPE" == "darwin"* ]]; then
		echo "Applying Darwin patch"
		sed "s/,--version-script//g" build/make/Makefile > build/make/Makefile.patched
		sed "s/-Wl,--no-undefined -Wl,-soname/-Wl,-undefined,error -Wl,-install_name/g" build/make/Makefile.patched > build/make/Makefile
	fi

	execute ./configure --prefix="${WORKSPACE}" --disable-unit-tests --disable-shared --as=yasm
	execute make -j $MJOBS
	execute make install

	build_done "libvpx"
fi
CONFIGURE_OPTIONS+=("--enable-libvpx")

if build "xvidcore"; then
	download "https://downloads.xvid.com/downloads/xvidcore-1.3.7.tar.gz"
	cd build/generic || exit
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	if [[ -f ${WORKSPACE}/lib/libxvidcore.4.dylib ]]; then
		execute rm "${WORKSPACE}/lib/libxvidcore.4.dylib"
	fi

	if [[ -f ${WORKSPACE}/lib/libxvidcore.so ]]; then
		execute rm "${WORKSPACE}"/lib/libxvidcore.so*
	fi

	build_done "xvidcore"
fi
CONFIGURE_OPTIONS+=("--enable-libxvid")

if build "vid_stab"; then
	download "https://github.com/georgmartius/vid.stab/archive/v1.1.0.tar.gz" "vid.stab-1.1.0.tar.gz"
	execute cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="${WORKSPACE}" -DUSE_OMP=OFF -DENABLE_SHARED=off .
	execute make
	execute make install

	build_done "vid_stab"
fi
CONFIGURE_OPTIONS+=("--enable-libvidstab")

if build "av1"; then
	download "https://aomedia.googlesource.com/aom/+archive/b52ee6d44adaef8a08f6984390de050d64df9faa.tar.gz" "av1.tar.gz" "av1"
	make_dir "$PACKAGES"/aom_build
	cd "$PACKAGES"/aom_build || exit
	execute cmake -DENABLE_TESTS=0 -DCMAKE_INSTALL_PREFIX="${WORKSPACE}" -DCMAKE_INSTALL_LIBDIR=lib "$PACKAGES"/av1
	execute make -j $MJOBS
	execute make install

	build_done "av1"
fi
CONFIGURE_OPTIONS+=("--enable-libaom")

##
## audio library
##

if build "opencore"; then
	download "https://deac-riga.dl.sourceforge.net/project/opencore-amr/opencore-amr/opencore-amr-0.1.5.tar.gz"
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	build_done "opencore"
fi
CONFIGURE_OPTIONS+=("--enable-libopencore_amrnb" "--enable-libopencore_amrwb")

if build "lame"; then
	download "https://netcologne.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz"
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	build_done "lame"
fi
CONFIGURE_OPTIONS+=("--enable-libmp3lame")

if build "opus"; then
	download "https://archive.mozilla.org/pub/opus/opus-1.3.1.tar.gz"
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	build_done "opus"
fi
CONFIGURE_OPTIONS+=("--enable-libopus")

if build "libogg"; then
	download "https://ftp.osuosl.org/pub/xiph/releases/ogg/libogg-1.3.3.tar.gz"
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install
	build_done "libogg"
fi

if build "libvorbis"; then
	download "https://ftp.osuosl.org/pub/xiph/releases/vorbis/libvorbis-1.3.6.tar.gz"
	execute ./configure --prefix="${WORKSPACE}" --with-ogg-libraries="${WORKSPACE}"/lib --with-ogg-includes="${WORKSPACE}"/include/ --enable-static --disable-shared --disable-oggtest
	execute make -j $MJOBS
	execute make install

	build_done "libvorbis"
fi
CONFIGURE_OPTIONS+=("--enable-libvorbis")

if build "libtheora"; then
	download "https://ftp.osuosl.org/pub/xiph/releases/theora/libtheora-1.1.1.tar.gz"
	sed "s/-fforce-addr//g" configure > configure.patched
	chmod +x configure.patched
	mv configure.patched configure
	execute ./configure --prefix="${WORKSPACE}" --with-ogg-libraries="${WORKSPACE}"/lib --with-ogg-includes="${WORKSPACE}"/include/ --with-vorbis-libraries="${WORKSPACE}"/lib --with-vorbis-includes="${WORKSPACE}"/include/ --enable-static --disable-shared --disable-oggtest --disable-vorbistest --disable-examples --disable-asm --disable-spec
	execute make -j $MJOBS
	execute make install

	build_done "libtheora"
fi
CONFIGURE_OPTIONS+=("--enable-libtheora")

if build "fdk_aac"; then
	download "https://sourceforge.net/projects/opencore-amr/files/fdk-aac/fdk-aac-2.0.1.tar.gz/download?use_mirror=gigenet" "fdk-aac-2.0.1.tar.gz"
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	build_done "fdk_aac"
fi
CONFIGURE_OPTIONS+=("--enable-libfdk-aac")


##
## image library
##

if build "libwebp"; then
	download "https://github.com/webmproject/libwebp/archive/v1.1.0.tar.gz" "libwebp-1.1.0.tar.gz"
	make_dir build
	cd build || exit
	execute cmake -DCMAKE_INSTALL_PREFIX="${WORKSPACE}" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_BINDIR=bin -DCMAKE_INSTALL_INCLUDEDIR=include -DENABLE_SHARED=OFF -DENABLE_STATIC=ON ../
	execute make -j $MJOBS
	execute make install

	build_done "libwebp"
fi
CONFIGURE_OPTIONS+=("--enable-libwebp")


##
## other library
##

if build "libsdl"; then
	download "https://www.libsdl.org/release/SDL2-2.0.12.tar.gz"
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	build_done "libsdl"
fi

if build "srt"; then
	download "https://github.com/Haivision/srt/archive/v1.4.1.tar.gz" "srt-1.4.1.tar.gz"
	export OPENSSL_ROOT_DIR="${WORKSPACE}"
	export OPENSSL_LIB_DIR="${WORKSPACE}"/lib
	export OPENSSL_INCLUDE_DIR="${WORKSPACE}"/include/
	execute cmake . -DCMAKE_INSTALL_PREFIX="${WORKSPACE}" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_BINDIR=bin -DCMAKE_INSTALL_INCLUDEDIR=include -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DENABLE_APPS=OFF -DUSE_STATIC_LIBSTDCXX=ON
	execute make install

	if [ -n "$LDEXEFLAGS" ]; then
		sed -i.backup 's/-lgcc_s/-lgcc_eh/g' "${WORKSPACE}"/lib/pkgconfig/srt.pc # The -i.backup is intended and required on MacOS: https://stackoverflow.com/questions/5694228/sed-in-place-flag-that-works-both-on-mac-bsd-and-linux
	fi

	build_done "srt"
fi
CONFIGURE_OPTIONS+=("--enable-libsrt")

# Build libass start
if build "fontconfig"; then
	download "https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.13.93.tar.xz"
	execute ./configure --prefix="${WORKSPACE}" --disable-docs --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	build_done "fontconfig"
fi

if build "freetype2"; then
	download "https://download.savannah.gnu.org/releases/freetype/freetype-2.10.4.tar.xz"
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	build_done "freetype2"
fi

if build "graphite2"; then
	download "https://github.com/silnrsi/graphite/releases/download/1.3.14/graphite2-1.3.14.tgz"
	execute cmake -DCMAKE_INSTALL_PREFIX="${WORKSPACE}" -DENABLE_SHARED=off -DBUILD_SHARED_LIBS=OFF -DENABLE_STATIC=ON .
	execute make -j $MJOBS
	execute make install

	build_done "graphite2"
fi

if build "harfbuzz"; then
	download "https://github.com/harfbuzz/harfbuzz/releases/download/2.7.4/harfbuzz-2.7.4.tar.xz"
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	build_done "harfbuzz"
fi

if build "fribidi"; then
	download "https://github.com/fribidi/fribidi/releases/download/v1.0.10/fribidi-1.0.10.tar.xz"
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	build_done "fribidi"
fi

if build "libass"; then
	download "https://github.com/libass/libass/releases/download/0.15.0/libass-0.15.0.tar.gz"
	execute autoreconf -fiv
	execute ./configure --prefix="${WORKSPACE}" --disable-shared --enable-static
	execute make -j $MJOBS
	execute make install

	build_done "libass"
fi
CONFIGURE_OPTIONS+=("--enable-libass")
# Build libass end


##
## HWaccel library
##

if [[ "$OSTYPE" == "linux-gnu" ]]; then
	if command_exists "nvcc" ; then
		if build "nv-codec"; then
			download "https://github.com/FFmpeg/nv-codec-headers/releases/download/n11.0.10.0/nv-codec-headers-11.0.10.0.tar.gz"
			execute make PREFIX="${WORKSPACE}"
			execute make install PREFIX="${WORKSPACE}"
			build_done "nv-codec"
		fi
		CFLAGS+=" -I/usr/local/cuda/include"
		LDFLAGS+=" -L/usr/local/cuda/lib64"
		CONFIGURE_OPTIONS+=("--enable-cuda-nvcc" "--enable-cuvid" "--enable-nvenc" "--enable-cuda-llvm")

		if [ -z "$LDEXEFLAGS" ]; then
			CONFIGURE_OPTIONS+=("--enable-libnpp") # Only libnpp cannot be statically linked.
		fi

		# https://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards/
		CONFIGURE_OPTIONS+=("--nvccflags=-gencode arch=compute_52,code=sm_52")
	fi

	# Vaapi doesn't work well with static links FFmpeg.
	if [ -z "$LDEXEFLAGS" ]; then
		# If the libva development SDK is installed, enable vaapi.
		if library_exists "libva" ; then
			if build "vaapi"; then
				build_done "vaapi"
			fi
			CONFIGURE_OPTIONS+=("--enable-vaapi")
		fi
	fi
fi


##
## FFmpeg
##

build "ffmpeg"
download "https://ffmpeg.org/releases/ffmpeg-4.3.1.tar.bz2"
# shellcheck disable=SC2086
./configure "${CONFIGURE_OPTIONS[@]}" \
	--disable-debug \
	--disable-doc \
	--disable-shared \
	--enable-gpl \
	--enable-version3 \
	--enable-nonfree \
	--enable-pthreads \
	--enable-static \
	--disable-ffplay \
	--extra-cflags="${CFLAGS}" \
	--extra-ldexeflags="${LDEXEFLAGS}" \
	--extra-ldflags="${LDFLAGS}" \
	--extra-libs="${EXTRALIBS}" \
	--pkgconfigdir="$WORKSPACE/lib/pkgconfig" \
	--pkg-config-flags="--static" \
	--prefix="${WORKSPACE}"

execute make -j $MJOBS
execute make install

INSTALL_FOLDER="/usr/local/bin"

if command_exists "sudo"; then
    sudo mv "$WORKSPACE/bin/ffmpeg" "$INSTALL_FOLDER/ffmpeg"
    sudo mv "$WORKSPACE/bin/ffprobe" "$INSTALL_FOLDER/ffprobe"
    echo "Done. FFmpeg is now installed to your system."
else
    mv "$WORKSPACE/bin/ffmpeg" "$INSTALL_FOLDER/ffmpeg"
    mv "$WORKSPACE/bin/ffprobe" "$INSTALL_FOLDER/ffprobe"
    echo "Done. FFmpeg is now installed to your system."
fi

exit 0
