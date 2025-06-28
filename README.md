# Build FFmpeg with xfade-easing on Windows

## Summary

A Bash script to automate building FFmpeg
incorporating the [xfade-easing](https://github.com/scriptituk/xfade-easing) patches to the xfade filter
natively from source on Windows under MSYS2.

It can build
- a minimal static version with just x264+zlib using MSVC or ClangCL
- a richer dynamic configuration using clang or gcc toolchains under Mingw64.

There are other, better FFmpeg Windows builder repos on GitHub but this one applies the patch for [xfade-easing](https://github.com/scriptituk/xfade-easing).

## Usage

1. follow the [MSYS2 installation instructions](https://www.msys2.org)

1. launch a MSYS2 Environment terminal from a shortcut in the Windows Start Menu (MSYS2 folder)
   or run `C:\msys64\msys2_shell.cmd -env` from a Command Prompt window
   where `env` is one of `msys`/`urct64`/`clang64`/`clangarm64`/`mingw64`

   - MSYS environment (default) for a minimal static build using the MSVC or ClangCL toolchain
     - requires Microsoft Visual C++ installed and
       [msys2-vcvars.sh](https://github.com/scriptituk/msys2-vcvars/blob/main/msys2-vcvars.sh)
       in same directory as ffmpeg-makexe\.sh
     - requires Visual Studio [Clang components](https://learn.microsoft.com/en-us/cpp/build/clang-support-msbuild#install-1)
       to use the MSVC-compatible clang-cl compiler
   - UCRT64 environment for a dynamic build using the gcc toolchain
   - CLANG64 environment for a dynamic build using the clang toolchain
   - CLANGARM64 environment for a dynamic build using the clang toolchain (untested)
   - MINGW64 environment for a dynamic build using the old msvcrt library (not recommended)

   the type of build is determined by environment variable MSYSTEM which defaults to MSYS

   for ClangCL run `export CC=clang-cl`

1. download and run [ffmpeg-makexe.sh](ffmpeg-makexe.sh);
   it creates binaries in
   `/opt/scriptituk/<env>/dist/`
   where `<env>` is the MSYS2 MinGW environment, or `msvc` or `clangcl` for the MSYS environment

1. manually copy the built binaries to `C:\Program Files\` and edit the `%PATH%` accordingly

The script downloads all the required sources automatically
and installs command tools and environment toolchains using `pacman`.

## Details

There are two versions: a static ffmpeg.exe and a [7-zip](https://www.7-zip.org/) archive containing ffmpeg.exe and dependent DLLs.

### Static MSVC builds

The MSYS environment builds a minimal static ffmpeg.exe with x264 encoding and zlib for PNG decoding.
It is based on [Roxlu’s guide](https://www.roxlu.com/2019/062/compiling-ffmpeg-with-x264-on-windows-10-using-msvc).

It executes the Visual Studio `vcvarsall.bat` script to ingest the MSVC development environment using
[msys2-vcvars](https://github.com/scriptituk/msys2-vcvars) .

If more than one instance of `vcvarsall.bat` is found then set `VCVARSALL_PATH` to the absolute path (Windows or Unix)
of the required instance.

To compile with `clang-cl` instead of `cl`, do `export CC=clang-cl` first, or run `CC=clang-cl ffmpeg-makexe.sh`.

#### Configuration:

```
    --extra-version=scriptituk/xfade-easing  
    --prefix=/opt/scriptituk/msys  
    --pkg-config=pkgconf --pkg-config-flags=--static  
    --enable-static --disable-shared --toolchain=msvc  
    --target-os=win64 --arch=x86_64 --enable-x86asm  
    --enable-gpl --enable-libx264 --enable-zlib  
    --disable-debug --disable-doc  
    --extra-cflags='-utf-8 -MT -wd4090 -wd4101 -wd4113 -wd4114 -wd4133 -Wv:12'
```

(clang-cl is the same except for --prefix, --shlibdir, --toolchain)

ClangCL builds slower than MSVC and produces larger binaries but runs faster.

### Shared clang/gcc builds

The CLANG64/UCRT64/etc. environments build a ffmpeg.7z archive containing ffmpeg.exe and all its constituent DLLs.
Requires [7-zip](https://www.7-zip.org/download.html).

Extract to `C:\Program Files\`.
It creates a folder `FFmpeg\`.

#### Configuration:

```
    --extra-version=scriptituk/xfade-easing
    --prefix=/opt/scriptituk/clang64 --shlibdir=/opt/scriptituk/clang64/so
    --arch=x86_64 --target-os=mingw32 --cc=clang --cxx=clang++
    --disable-static --enable-shared
    --disable-ffplay --disable-debug --disable-doc
    --enable-dxva2 --enable-d3d11va --enable-d3d12va --enable-frei0r --enable-gmp
    --enable-gnutls --enable-gpl --enable-iconv --enable-libaom --enable-libass
    --enable-libbluray --enable-libcaca --enable-libdav1d --enable-libfontconfig
    --enable-libfreetype --enable-libfribidi --enable-libgme --enable-libgsm
    --enable-libharfbuzz --enable-libjxl --enable-libmodplug --enable-libmp3lame
    --enable-libopencore_amrnb --enable-libopencore_amrwb --enable-libopenjpeg
    --enable-libopus --enable-librsvg --enable-librtmp --enable-libssh
    --enable-libsoxr --enable-libspeex --enable-libsrt --enable-libvidstab
    --enable-libx264 --enable-libxvid --enable-libvpx --enable-libwebp
    --enable-libxml2 --enable-libzimg --enable-libzvbi --enable-openal
    --enable-pic --enable-postproc --enable-runtime-cpudetect --enable-swresample
    --enable-version3 --enable-zlib --enable-librav1e --enable-libvpl
    --enable-libsvtav1 --enable-liblc3
```

(UCRT64 is the same except for --prefix, --shlibdir, --cc, --cxx which show ucrt64 and gcc; similarly other environments)

The clang toolchain builds faster than gcc and produces smaller binaries but runs slightly slower.

## Performance

Interestingly, ClangCL runs fastest, then MSVC, with MinGW gcc a little faster than MinGW clang.

## See also

- [scriptituk/xfade-easing](https://github.com/scriptituk/xfade-easing) – Easing and extensions for FFmpeg Xfade filter
- [scriptituk/msys2-vcvars](https://github.com/scriptituk/msys2-vcvars) – Import MSVC environment variables into Msys2
- [Msys2 Environments](https://www.msys2.org/docs/environments/) – environment for building, installing and running native Windows software
- [Visual Studio Community Edition](https://visualstudio.microsoft.com/vs/community/) – free Microsoft Visual Studio Community edition
- [ffmpeg-windows-build-helpers](https://github.com/rdp/ffmpeg-windows-build-helpers) – cross compiles Windows 32/64-bit FFmpeg tools and dependencies
- [media-autobuild_suite](https://github.com/m-ab-s/media-autobuild_suite) – Windows Batchscript builds Mingw-w64/GCC ffmpeg and other media tools
- [Roxlu’s guide](https://www.roxlu.com/2019/062/compiling-ffmpeg-with-x264-on-windows-10-using-msvc) – Compiling FFmpeg with X264 on Windows 10 using MSVC
