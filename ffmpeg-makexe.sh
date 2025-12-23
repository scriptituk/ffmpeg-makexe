#!/usr/bin/env bash

#=========================================================================================
# FFmpeg+xfade-easing Windows build by Raymond Luckhurst, Scriptit UK, https://scriptit.uk
# GitHub: https://github.com/scriptituk/ffmpeg-makexe   February 2025   MIT Licence
#=========================================================================================

while getopts "i:lgc:nrd:h" opt; do
    case $opt in
        i) o_install=$OPTARG ;;
        l) o_llvm=true ;;
        g) o_gpu=true ;;
        c) o_config=$OPTARG ;;
        n) o_noxe=true ;;
        r) o_rebuild=true ;;
        d) o_debug=$OPTARG ;;
        h) o_help=true ;;
    esac
done

# functions ----------

_help() {
    cat << EOT
Simple FFmpeg builder for the Windows platform, optionally with xfade-easing

Requires MSYS2: follow instructions at https://www.msys2.org
UCRT64/CLANG64/CLANGARM64/MINGW64 environment builds a feature-rich shared version
MSYS environment builds a basic static version (requires Microsoft Visual Studio)
 (to use LLVM/clang-cl instead of MSVC use option -l)
All requisite tools are installed as needed via a package manager (pacman)
 (ffmpeg too, to obviate building its constituent external libraries)
The FFmpeg release built is the latest version supported by pacman

Usage: ./ffmpeg-makexe.sh [options]
Options:
    -i <dir> set installation root (default /opt/scriptituk)
    -l use LLVM (clang-cl) Visual Studio toolset instead of MSVC (MSYS only)
    -g do not disable GPU options that can break configure (not MSYS)
    -c <opts> append options to ffmpeg configure command (not MSYS)
       (-c cannot enable external libraries that are not installed)
    -n do not patch in xfade-easing superset, just build vanilla FFmpeg instead
    -r rebuild from scratch (removes cached downloads and build trees)
    -d <flags> set debug flags (e.g. -d SL):
       S trace shell command execution (set -x)
       M trace makefile recipe execution (--debug=print)
       L enable logging to ./ffmpeg-makexe-<environment>.log
       T use ./tmp/ for temporary files and keep them on exit
    -h print this message

See https://github.com/scriptituk/ffmpeg-makexe for more information
See https://github.com/scriptituk/xfade-easing for xfade-easing usage
See https://github.com/scriptituk/msys2-mcvars used to ingest MSVC environment
EOT
}

_log() { # self logging - see https://stackoverflow.com/questions/3173131/
    log=$(realpath $PWD/${0%.*}-$env.log)
    > $log
    exec > >(tee -ia $log)
    exec 2> >(tee -ia $log >&2)
    echo "logging to $log"
}

_err() { # show error and abort
    echo -e "Error: $1" >&2
    exit 64 # unreserved exit code
}

_cmd() { # execute command quietly, abort on error
    local ret
    echo -e "$1" >> $log
    ret=$($1 2>&1)
    [[ $? -ne 0 ]] && _err "$1\n\t$ret"
}

_req() { # install required command if not available
    _cmd "pacman -Sq --needed --noconfirm --noprogressbar $1"
}

_get() { # download remote file
    local url="$1"
    dest=$ddown/${2-$(basename "$url")}
    mkdir -p $ddown
    [[ ! -f $dest ]] && _cmd "wget -nv -O $dest $url"
}

_ldd() { # get shared libraries in environment
    ldd "$1" | awk -v env="^/$env/" '$2 == "=>" && $3 ~ env { print $3 }'
}

_chkxe() { # check compiled xfade-easing corresponds with -n option
    local noxe isxe
    ! test -n "$o_noxe"; noxe=$?
    ! grep -q 'xfade-easing\.h' $build/libavfilter/vf_xfade.d; isxe=$?
    [[ $isxe -eq $noxe ]] && rm -f $build/libavfilter/vf_xfade.o
    if [[ -n $o_noxe ]]; then
        cp -p $xfd/vf_xfade.c.orig $xfd/vf_xfade.c
    else
        cp -p $xfd/vf_xfade.c.xe $xfd/vf_xfade.c
    fi
}

_init() { # download source tarball and set vars for build
    _get $1 # sets $dest
    tar -tzf $dest > /dev/null # check integrity
    [[ $? -ne 0 ]] && _err "tar -tzf $dest  failed"
    echo "initialise $env $target ------------------------------"
    target=$(tar -tzf $dest | head -1 | sed 's,/,,')
    package=$(cut -d- -f1 <<<$target)
    build=$dbuild/$target
    src=$dsrc/$target
    [[ ! -d $src ]] && tar -C $dsrc -xf $dest
    xfd=$src/libavfilter
    mkdir -p $build
    rsrc=$(realpath --relative-to=$build $src)
}

# begin setup ----------

[[ -n $o_help ]] && _help && exit 0

_help | head -1
echo 'See option -h for usage'

[[ -n $MSYSTEM ]] || _err 'env MSYSTEM undefined, is MSYS2 environment set?'
env=$(tr '[:upper:]' '[:lower:]' <<<$MSYSTEM)
if [[ $env = msys ]]; then
    [[ -n $o_llvm ]] && env=clangcl || env=msvc
    [[ $env = clangcl ]] && CC=clang-cl || CC=cl
else
    [[ -n $o_llvm ]] && _err "option -l is for MSYS environment, invalid for $MSYSTEM"
    [[ $env =~ clang ]] && CC=clang || CC=gcc
fi

echo 'begin ------------------------------'

[[ $o_debug =~ L ]] && _log || log=/dev/null
[[ $o_debug =~ S ]] && set -x
[[ $o_debug =~ M ]] && md='--debug=print'
if [[ $o_debug =~ T ]]; then
    TMP=$PWD/tmp
    mkdir -p $TMP
else
    TMP=$(mktemp -d -p $TMP fm-XXX)
    trap "rm -fr $TMP" EXIT
fi
export TMP

install=${o_install-/opt/scriptituk}
mpp=$MINGW_PACKAGE_PREFIX
extra_version=scriptituk/ffmpeg-makexe
arch=$MSYSTEM_CARCH
prefix=$install/$env
dbin=$prefix/bin
dinclude=$prefix/include
dlib=$prefix/lib
dso=$prefix/so
ddist=$prefix/dist
dvar=$install/var # root of build tree
dbuild=$dvar/build/$env
dsrc=$dvar/src
ddown=$dvar/downloads

# need base development tools
_req base-devel # patch
_req wget

# get ffmpeg release number from latest pacman version
rel=$(pacman -Si ${mpp:-mingw-w64-clang-$arch}-ffmpeg | awk '/Version/ {v=$3; sub(/-.*/,"",v); printf v}')
echo "building FFmpeg release $rel"

# rebuild
if [[ -n $o_rebuild ]]; then
    echo 'removing cached files'
    rm -fr $prefix $dbuild $ddown $dsrc
fi
mkdir -p $dsrc

# get ffmpeg source
ffmpeg_url=https://ffmpeg.org/releases/ffmpeg-$rel.tar.gz
_init $ffmpeg_url

# install xfade patch
XE_SRC=https://github.com/scriptituk/xfade-easing/raw/refs/heads/main/src
_get $XE_SRC/xfade-easing.h
_get $XE_SRC/vf_xfade.patch
if ! cmp -s $ddown/xfade-easing.h $xfd/xfade-easing.h; then
    cp $ddown/xfade-easing.h $xfd/
fi
if ! cmp -s $ddown/vf_xfade.patch $src/vf_xfade.patch; then
    cp $ddown/vf_xfade.patch $src/
    patch -b -u -N -p0 -d $src -i vf_xfade.patch
    cp -p $xfd/vf_xfade.c $xfd/vf_xfade.c.xe
fi

echo "start $env build ------------------------------"

# ==================================================

case $env in

mingw64) echo "Warning: $env uses the old MSVCRT runtime library" ;&
ucrt64 | clang64 | clangarm64)

echo 'get externals ------------------------------'

# install essential tools
_req $mpp-toolchain
_req $mpp-nasm
_req p7zip

# install ffmpeg to get external components
_req $mpp-ffmpeg

pushd $build >> $log

echo "configure $package ------------------------------"
if [[ ! -f Makefile ]]; then
    STATIC=no # (experimental)
    echo "$rsrc/configure --extra-version=$extra_version \\" > conf
    echo "--prefix=$prefix --shlibdir=$dso \\" >> conf
    echo "--target-os=mingw32 --arch=$arch --cc=$CC --cxx=$CC++ \\" >> conf
if [[ $STATIC = yes ]]; then
    echo "--pkg-config-flags=--static --extra-ldexeflags=-static \\" >> conf
    echo "--enable-static --disable-shared \\" >> conf
else
    echo "--disable-static --enable-shared \\" >> conf
fi
    echo "--disable-debug --disable-ffplay --disable-doc \\" >> conf
    # get pacman ffmpeg conf then disable options that break the configuration
    ffmpeg -hide_banner -buildconf | tee conf.orig | d2u | sed -E '
        s/^\s*//; /^$/d;
        /(configuration|Exiting)/d;
        /--(prefix|logfile)=/d;
        /--(target-os|arch|cc|cxx)=/d;
        /able-(debug|stripping|play|doc|shared|static)$/d;
        s/$/ \\/
    ' >> conf
    if [[ -z $o_gpu ]]; then
        cat conf | sed -E '/--enable-(libplacebo|vulkan|nvenc|amf) /d' > _conf
        mv -f _conf conf
    fi
    [[ -n $o_config ]] && echo "$o_config \\" >> conf
    echo >> conf
    source ./conf
    [[ $? -ne 0 ]] && _err 'configure failed'
fi

echo "make $package ------------------------------"
_chkxe
make $md ECFLAGS=-Wno-declaration-after-statement || _err 'make failed'

echo "install $package ------------------------------"
[[ ffmpeg.exe -nt $dbin/ffmpeg.exe ]] && { make $md install || _err 'make install failed'; }

popd >> $log

echo "release $package ------------------------------"
if [[ $dbin/ffmpeg.exe -nt $ddist/ffmpeg.7z ]]; then
    zip=$ddist/FFmpeg
    rm -f $zip
    mkdir -p $zip
    dlls=($(_ldd $dbin/ffmpeg.exe))
    cp $dbin/ffmpeg.exe $dbin/ffprobe.exe $zip/
    while [[ ${#dlls[@]} -ne 0 ]]; do
        more=
        for l in "${dlls[@]}"; do
            b=$(basename $l)
            if [[ ! -f $zip/$b ]]; then
                if [[ -f $dso/$b ]]; then
                    l=$dso/$b
                else
                    more+=$(_ldd $l)
                fi
                echo -n " $b"
                cp $l $zip/
            fi
        done
        m="${dlls[*]}"
        dlls=()
        for l in $more; do
            [[ " $m " =~ " $l " ]] && continue
            echo -n " +$l"
            dlls+=($l)
        done
        echo " ${#dlls[@]} more"
    done
    rm -f $ddist/ffmpeg.7z
    7z a -mx7 $ddist/ffmpeg.7z $zip # see https://dotnetperls.com/7-zip-examples
    rm -fr $zip
fi

;; # end case

# ==================================================

# Start Menu MSYS or c:\msys64\msys2_shell.cmd [-msys]
msvc | clangcl)

if ! command -v $CC > /dev/null; then
    [[ -f msys2-vcvars.sh ]] || _err 'missing script msys2-vcvars.sh'
    [[ $o_debug =~ S ]] && DEBUG=yes
    source msys2-vcvars.sh
    vcvarsall x64 || _err 'vcvarsall failed'
fi

_req nasm
_req pkgconf
_req autotools

winclude=$(cygpath -awl $dinclude)
wlib=$(cygpath -awl $dlib)
export INCLUDE="$winclude;$INCLUDE"
export LIB="$wlib;$LIB"
export PKG_CONFIG_PATH=$dlib/pkgconfig:$PKG_CONFIG_PATH

# make zlib ----------

_init https://www.zlib.net/zlib-1.3.1.tar.gz

pushd $build >> $log

echo "make $package ------------------------------"
sed 's/-base:[0-9A-Fx]*//' $src/win32/Makefile.msc > Makefile.msc
# no clang-cl support
nmake -nologo \
    TOP=$src \
    CC=cl \
    CFLAGS='-nologo -W3 -O2' \
    LDFLAGS=-nologo \
    RCFLAGS='-nologo -dWIN32 -r' \
    -f Makefile.msc
[[ $? -ne 0 ]] && _err 'nmake failed'

echo "install $package ------------------------------"
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

popd >> $log

# make x264 ----------

_init https://code.videolan.org/videolan/x264/-/archive/stable/x264-stable.tar.gz
# the core version is in $src/x264.h, e.g. #define X264_BUILD 165
# $src/version.sh emits #define X264_POINTVER "0.165.x"

pushd $build >> $log

echo "configure $package ------------------------------"
if [[ ! -f Makefile ]]; then
    # config files - see https://www.gnu.org/software/gettext/manual/html_node/config_002eguess.html
    _get 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD' config.guess
    _get 'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD' config.sub
    cmp -s $ddown/config.guess $src/config.guess || cp -f $ddown/config.guess $src/
    cmp -s $ddown/config.sub $src/config.sub || cp -f $ddown/config.sub $src/
    # no clang-cl support
    CC=cl \
    $src/configure --prefix=$prefix --disable-cli --enable-static
    [[ $? -ne 0 ]] && _err 'configure failed'
fi

echo "make $package ------------------------------"
make $md || _err 'make failed'

echo "install $package ------------------------------"
[[ libx264.lib -nt $dlib/libx264.lib ]] && { make $md install || _err 'make install failed'; }

popd >> $log

# make ffmpeg ----------

_init $ffmpeg_url

pushd $build >> $log

echo "configure $package ------------------------------"
if [[ ! -f Makefile ]]; then
    # relative paths needed to help Msys2 automatic path conversion
    tc=--toolchain=msvc
    if [[ -n $o_llvm ]]; then
        tc='--cc=clang-cl --cxx=clang-cpp'
        tc+=' --ld=lld-link --host-ld=lld-link'
        tc+=' --ar=llvm-ar --nm=llvm-nm'
        tc+=' --ranlib=llvm-ranlib --strip=llvm-strip'
        tc+=" --windres=$rsrc/compat/windows/mswindres"
    fi
    TMP=$(realpath --relative-to=$PWD $TMP) \
    $rsrc/configure --extra-version=$extra_version \
        --prefix=$prefix --enable-static --disable-shared \
        --target-os=win64 --arch=$arch --pkg-config-flags=--static \
        $tc \
        --extra-cflags='-utf-8 -MT -wd4090 -wd4101 -wd4113 -wd4114 -wd4133 -Wv:12' \
        --disable-ffplay --disable-debug --disable-doc \
        --enable-gpl --enable-libx264 --enable-zlib
    [[ $? -ne 0 ]] && _err 'configure failed'
fi

echo "make $package ------------------------------"
_chkxe
[[ -n $o_llvm ]] && ec=ECFLAGS=-Wno-declaration-after-statement || ec=
make $md $ec || _err 'make failed'

echo "install $package ------------------------------"
[[ ffmpeg.exe -nt $dbin/ffmpeg.exe ]] && { make $md install || _err 'make install failed'; }

popd >> $log

echo "release $package ------------------------------"
if [[ $dbin/ffmpeg.exe -nt $ddist/ffmpeg.exe ]]; then
    mkdir -p $ddist
    ln -f $dbin/ffmpeg.exe $dbin/ffprobe.exe $ddist/
fi

;; # end case

esac

echo 'test ------------------------------'
PATH="$dso:$PATH" # for libs
if [[ -n $o_noxe ]]; then
    $dbin/ffmpeg.exe -hide_banner -buildconf | grep $extra_version
else
    $dbin/ffmpeg.exe -hide_banner -help filter=xfade | grep easing
fi
if [[ $? -ne 0 ]]; then
    _err 'oops, something went wrong'
else
    wpff=$(cygpath -awl '/c/Program Files/FFmpeg')
    wdist=$(cygpath -awl $ddist)
    bat=$ddist/install-ffmpeg.bat
    wbat=$(cygpath -awl $bat)
    del="@if exist \"$wpff\" del /q \"$wpff\""$'\n'
    cp="${del}xcopy $wdist\\ff*.exe \"$wpff\\\" /y"
    if [[ -f $ddist/ffmpeg.7z ]]; then
        cp="@where 7z 2> nul || ( echo \"7z not found\" & exit /b )"$'\n'
        cp+="${del}7z x $wdist\\ffmpeg.7z -o\"${wpff%\\*}\""
    fi
    cat << EOT | u2d > $bat
$cp
@rem TODO: set HKLM Path without changing REG_EXPAND_SZ to REG_SZ type
@if "%Path%"=="%Path:$wpff;=%" set Path=%Path%;$wpff;
EOT
    echo "success"
    echo "run $wbat in Windows Administrator Command Prompt to install into $wpff\\"
fi

echo 'done ------------------------------'

