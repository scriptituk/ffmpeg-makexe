#!/usr/bin/env bash

#==========================================================================================
# FFmpeg + xfade-easing Windows build by Raymond Luckhurst, Scriptit UK, https://scriptit.uk
# GitHub: https://github.com/scriptituk/ffmpeg-makexe   February 2025   MIT Licence
#==========================================================================================

# Simple Windows platform FFmpeg builder incorporating xfade-easing
#
# Builds FFmpeg on Windows with libavfilter/vf_xfade.c patched for xfade-easing
# Requires MSYS2 - follow instructions at https://www.msys2.org
# UCRT64/CLANG64/CLANGARM64/MINGW64 environment tools get installed as needed
# MSYS environment builds a basic MSVC version (requires Microsoft Visual Studio)
# To use LLVM clang-cl instead of MSVC cl, export CC=clang-cl under MSYS
#
# See https://github.com/scriptituk/xfade-easing xfade-easing repo
# See https://github.com/scriptituk/msys2-mcvars used to ingest MSVC environment

DEBUG=${DEBUG-no} # set yes to echo commands for debugging

if [[ $DEBUG == yes ]]; then
    TMP=$PWD/tmp; mkdir -p $TMP
    set -x
else
    TMP=$(mktemp -d -p $TMP fm-XXX)
    trap "rm -fr $TMP" EXIT
fi
export TMP

# set the ffmpeg stable tarball
FFMPEG_REPO=https://ffmpeg.org/releases/ffmpeg-7.1.tar.gz

# set installation directory
INSTALL=/opt/scriptituk

# end of setup ----------

_log() { # self logging - see https://stackoverflow.com/questions/3173131/
    log=${0%.*}-$ENV.log
    > $log
    exec > >(tee -ia $log)
    exec 2> >(tee -ia $log >&2)
}

_err() { # show error and abort
    echo "Error: $1" >&2
    exit 64
}

_chk() { # test if command works
    command -v $1 > /dev/null
    local chk=$?
    [[ $chk -ne 0 ]] && echo "Command '$1' not found" >&2
    return $chk
}

_req() { # install required command if not available
    _chk $1 || pacman -Sq --needed --noconfirm ${2-$1}
}

_get() { # download remote file
    local url="$1"
    dest=$ddown/${2-$(basename "$url")}
    mkdir -p $ddown
    [[ ! -f $dest ]] && wget -O $dest "$url"
    [[ ! -f $dest ]] && _err "wget '$url' failed"
}

_init() { # download source tarball and set vars for build
    _get $1 # sets $dest
    target=$(tar -tzf $dest | head -1 | sed 's,/,,')
    echo "initialise $ENV $target ------------------------------"
    build=$dbuild/$target
    src=$dsrc/$target
    [[ ! -d $src ]] && tar -C $dsrc -kxf $dest
    mkdir -p $build
    rsrc=$(realpath --relative-to=$build $src)
}

_req wget

[[ -n $MSYSTEM ]] || _err 'env MSYSTEM undefined, is msys2 environment set?'

ENV=$(tr '[:upper:]' '[:lower:]' <<<$MSYSTEM)
if [[ $ENV = msys ]]; then
    [[ ${CC-cl} =~ clang ]] && ENV=clangcl || ENV=msvc
    [[ $ENV = clangcl ]] && CC=clang-cl || CC=cl
else
    [[ $ENV =~ clang ]] && CC=clang || CC=gcc
fi

_log

arch=$MSYSTEM_CARCH
prefix=$INSTALL/$ENV
dbin=$prefix/bin
dinclude=$prefix/include
dlib=$prefix/lib
dso=$prefix/so
ddist=$prefix/dist
dvar=$INSTALL/var # root of build tree
dbuild=$dvar/build/$ENV
dsrc=$dvar/src
ddown=$dvar/downloads
dcache=$dvar/cache
mkdir -p $dsrc $dcache

# need base development tools
_req patch base-devel

# get ffmpeg
_init $FFMPEG_REPO
EXTRA_VERSION=scriptituk/xfade-easing

# install xfade patch
XE_SRC=https://github.com/scriptituk/xfade-easing/raw/refs/heads/main/src
_get $XE_SRC/xfade-easing.h
_get $XE_SRC/vf_xfade.patch
if [[ $ddown/xfade-easing.h -nt $src/libavfilter/xfade-easing.h ]]; then
    cp $ddown/xfade-easing.h $src/libavfilter/
    rm -f $src/libavfilter/vf_xfade.o
fi
if [[ $ddown/vf_xfade.patch -nt $src/libavfilter/vf_xfade.c ]]; then
    cp $ddown/vf_xfade.patch $src/
    patch -b -u -N -p0 -d $src -i vf_xfade.patch
fi

# config files - see https://www.gnu.org/software/gettext/manual/html_node/config_002eguess.html
_get 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD' config.guess
_get 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD' config.sub

STATIC=no # (experimental) MSYS is static-only, others dynamic-only

echo "start $ENV build ------------------------------"

# ==================================================

case $ENV in

mingw64) echo "Warning: $ENV uses the old MSVCRT runtime library" ;&
ucrt64 | clang64 | clangarm64)

MPP=$MINGW_PACKAGE_PREFIX

echo 'get externals ------------------------------'

# install essential tools
_req $CC $MPP-toolchain
_req nasm $MPP-nasm
_req 7z p7zip

# install ffmpeg to get external components
_req ffmpeg $MPP-ffmpeg

pushd $build

echo 'configure ------------------------------'
if [[ ! -f Makefile ]]; then
    echo "CC=$CC \\" > conf
    echo "$rsrc/configure --extra-version=$EXTRA_VERSION \\" >> conf
    echo "--prefix=$prefix --shlibdir=$dso \\" >> conf
    echo "--arch=$arch \\" >> conf
if [[ $STATIC == yes ]]; then
    echo "--pkg-config-flags=--static --extra-ldexeflags=-static \\" >> conf
    echo "--enable-static --disable-shared \\" >> conf
else
    echo "--disable-static --enable-shared \\" >> conf
fi
    echo "--disable-ffplay \\" >> conf
    # get pacman ffmpeg conf then disable options that break the build
    ffmpeg -hide_banner -buildconf | tee conf.orig | d2u | sed '
        s/^\s*//; /^$/d;
        /configuration:/d;
        /--prefix=/d;
        /--logfile=/d;
        /--arch=/d;
        /--disable-stripping/d;
        /--enable-shared/d;
# legacy - see https://trac.ffmpeg.org/wiki/TheoraVorbisEncodingGuide
/--enable-libtheora/d;
/--enable-libvorbis/d;
# these break configure
/--enable-libplacebo/d;
/--enable-vulkan/d;
/--enable-nvenc/d;
/--enable-amf/d;
# these break -static
#/--enable-gnutls/d;
#/--enable-libbluray/d;
#/--enable-libfontconfig/d;
#/--enable-libfreetype/d;
#/--enable-libharfbuzz/d;
#/--enable-libfribidi/d;
#/--enable-libjxl/d;
#/--enable-libgsm/d;
#/--enable-libmodplug/d;
#/--enable-librsvg/d;
#/--enable-librtmp/d;
#/--enable-libsoxr/d;
#/--enable-libssh/d;
#/--enable-libvidstab/d;
#/--enable-openal/d;
# these break make
/--enable-libx265/d;
# test - keep it simple
#/zlib/!d;
        s/$/ \\/
        ' >> conf
        echo >> conf
    source ./conf
fi

echo 'make ------------------------------'
make ECFLAGS=-Wno-declaration-after-statement

echo 'install ------------------------------'
[[ ffmpeg.exe -nt $dbin/ffmpeg.exe ]] && make install

popd

echo 'release ------------------------------'
if [[ $dbin/ffmpeg.exe -nt $ddist/ffmpeg.7z ]]; then
    tmp=$TMP/dll
    mkdir -p $tmp
    rm -f $tmp/*
    dlls=($(ldd $dbin/ffmpeg.exe | awk '!/Windows/ { print $3 }'))
    ln $dbin/ffmpeg.exe $tmp/
    while [[ ${#dlls[@]} -ne 0 ]]; do
        more=
        for d in "${dlls[@]}"; do
            b=$(basename $d)
            if [[ ! -f $tmp/$b ]]; then
                if [[ -f $dso/$b ]]; then
                    d=$dso/$b
                else
                    more+=$(ldd $d | awk -v d=$d '!/Windows/ { if ($3 != d) print " " $3 }')
                fi
                echo -n " $b"
                ln $d $tmp/
            fi
        done
        m="${dlls[*]}"
        dlls=()
        for d in $more; do
            [[ " $m " =~ " $d " ]] && continue
            echo -n " +$d"
            dlls+=($d)
        done
        echo " ${#dlls[@]} more"
    done
    rm -f $ddist/ffmpeg.7z
    7z a -mx9 $ddist/ffmpeg.7z $tmp
    7z rn $ddist/ffmpeg.7z $(basename $tmp)/ FFmpeg/
    rm -fr $tmp
fi

;; # end build

# ==================================================

# Start Menu MSYS or c:\msys64\msys2_shell.cmd [-msys]
msvc | clangcl)

if ! command -v $CC > /dev/null; then
    [[ -f msys2-vcvars.sh ]] || _err 'cannot source msys2-vcvars.sh'
    source msys2-vcvars.sh
    vcvarsall x64 || _err 'vcvarsall failed'
fi

_req nasm
_req pkg-config pkgconf
_req autoconf autotools

winclude=$(cygpath -awl $dinclude)
wlib=$(cygpath -awl $dlib)
export INCLUDE="$winclude;$INCLUDE"
export LIB="$wlib;$LIB"
export PKG_CONFIG_PATH=$dlib/pkgconfig:$PKG_CONFIG_PATH

# make zlib ----------

_init https://www.zlib.net/zlib-1.3.1.tar.gz

pushd $build

echo 'make ------------------------------'
sed 's/-base:[0-9A-Fx]*//' $src/win32/Makefile.msc > Makefile.msc
# use cl not clang-cl
nmake -nologo \
    TOP=$src \
    CC=cl \
    CFLAGS='-nologo -MT -W3 -O2' \
    LDFLAGS=-nologo \
    RCFLAGS='-nologo -dWIN32 -r' \
    -f Makefile.msc

echo 'install ------------------------------'
if [[ zlib.lib -nt $dlib/zlib.lib ]]; then
    mkdir -p $dinclude $dlib/pkgconfig $dso
    sed 's/unistd.h/io.h/' $src/zconf.h.in > $dinclude/zconf.h
    cp $src/zlib.h $dinclude/
    cp zlib.lib $dlib/
    cp zlib1.dll $dso/
    sed "
        s,@prefix@,$prefix,
        s,@exec_prefix@,\${prefix},
        s,@libdir@,\${exec_prefix}/lib,
        s,@sharedlibdir@,\${exec_prefix}/so,
        s,@includedir@,\${prefix}/include,
        s,@VERSION@,${target#*-},
    " $src/zlib.pc.in > $dlib/pkgconfig/zlib.pc
fi

popd

# make x264 ----------

_init https://code.videolan.org/videolan/x264/-/archive/stable/x264-stable.tar.gz
# the core version is in $src/x264.h, e.g. #define X264_BUILD 164
# $src/version.sh emits #define X264_POINTVER "0.164.x"

pushd $build

echo 'configure ------------------------------'
if [[ ! -f Makefile ]]; then
    # use cl not clang-cl
    cmp -s $ddown/config.guess $src/config.guess || cp -f $ddown/config.guess $src/
    cmp -s $ddown/config.sub $src/config.sub || cp -f $ddown/config.sub $src/
    CC=cl \
    $src/configure --prefix=$prefix --enable-static --extra-cflags=-MT
fi

echo 'make ------------------------------'
make

echo 'install ------------------------------'
[[ libx264.lib -nt $dlib/libx264.lib ]] && make install

popd

# make ffmpeg ----------

_init $FFMPEG_REPO

pushd $build

lp=./libavcodec:./libavdevice:./libavfilter:./libavformat:./libavutil:./libpostproc:./libswscale:./libswresample
export LIB="$(cygpath -wp $lp);$LIB"

[[ $CC = cl ]] && tc=--toolchain=msvc || tc=--cc=$CC
[[ $CC = cl ]] && rc= || rc=--windres=$rsrc/compat/windows/mswindres
[[ $CC = cl ]] && ec= || ec=ECFLAGS=-Wno-declaration-after-statement
#[[ $CC = cl ]] && vp= || vp=--define-variable=prefix=$(realpath --relative-to=$PWD $prefix)

echo 'configure ------------------------------'
if [[ ! -f Makefile ]]; then
    # relative paths needed to help Msys2 automatic path conversion
    TMP=$(realpath --relative-to=$PWD $TMP) \
    CC=$CC \
    $rsrc/configure \
        --extra-version=$EXTRA_VERSION \
        --prefix=$prefix --shlibdir=$dso \
        --pkg-config-flags=--static \
        --enable-static --disable-shared \
        $tc --target-os=win64 --arch=$arch \
        $rc \
        --enable-gpl --enable-libx264 --enable-zlib \
        --disable-ffplay --disable-debug --disable-doc \
        --extra-cflags='-MT -wd4090 -wd4101 -wd4113 -wd4114 -wd4133 -Wv:12'
fi

echo 'make ------------------------------'
make $ec

echo 'install ------------------------------'
[[ ffmpeg.exe -nt $dbin/ffmpeg.exe ]] && make install

popd

echo 'release ------------------------------'
[[ $dbin/ffmpeg.exe -nt $ddist/ffmpeg.7z ]] && { mkdir -p $ddist; ln -f $dbin/ffmpeg.exe $ddist/; }

;; # end build

esac

echo 'done ------------------------------'

