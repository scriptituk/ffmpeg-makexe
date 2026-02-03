# Build FFmpeg with xfade-easing on Windows

## Summary

<img src="ffmpeg-makexe.svg" alt="Summary" width="120" align="right">

A simple Bash script to automate building FFmpeg natively from source on Windows under MSYS2,
optionally incorporating [xfade-easing] patches.

It can build:
- a shared (DLL) version with rich configuration using clang or gcc toolchains under Mingw64;\
  this does *not* build external libraries but links them in from a package-managed FFmpeg installation
- a minimal static version with x264+zlib using MSVC or LLVM/clang-cl toolsets

This is much simpler than other build scripts for FFmpeg on Windows that build the external libraries too.

The xfade superset filter [xfade-easing] adds enhanced cross-fade video transition effects by default,
but the `-n` option builds plain vanilla FFmpeg without it.

## Usage

1. Follow the [MSYS2 installation instructions](https://www.msys2.org).

1. Launch a MSYS2 Environment terminal from a shortcut in the Windows Start Menu (MSYS2 folder)
   or run `C:\msys64\msys2_shell.cmd -env` from a Command Prompt window
   where `env` is one of `msys`/`urct64`/`clang64`/`clangarm64`/`mingw64`:

   - MSYS environment (default) for a minimal static build using the MSVC or LLVM toolchain and UCRT runtime
     - requires Microsoft Visual C++ installed and [msys2-vcvars.sh] in same directory as [ffmpeg-makexe.sh]
     - requires Visual Studio [Clang components](https://learn.microsoft.com/en-us/cpp/build/clang-support-msbuild#install-1)
       to use the optional MSVC-compatible clang-cl compiler
   - UCRT64 environment for a shared build using the GCC toolchain and UCRT runtime
   - CLANG64 environment for a shared build using the Clang-LLVM toolchain and UCRT runtime
   - CLANGARM64 environment for a shared build using the Clang-LLVM toolchain *(untested)*
   - MINGW64 environment for a shared build using the old MSVCRT runtime *(not recommended)*

   The type of build is determined by environment variable MSYSTEM which defaults to MSYS.

   For clang-cl use option `-l` in the next step.

1. Download and run [ffmpeg-makexe.sh];
   it creates executables in
   `/opt/scriptituk/<env>/dist/`
   where `<env>` is the MSYS2 MinGW environment in lower-case,
   or `msvc` or `clangcl` for the MSYS environment (not `msys`).

1. To install into Windows, run the generated batch script from an Administrator Command Prompt:\
   `C:\msys64\opt\scriptituk\<env>\dist\install-ffmpeg.bat`\
   or manually copy/unzip the built binaries to `"C:\Program Files\FFmpeg\"`.

1. The `install-ffmpeg.bat` script amends the Windows `%Path%` but to do so manually run:\
   `set Path=%Path%;"C:\Program Files\FFmpeg;"`.\
   To persist the change use `regedit` to edit the `HKEY_LOCAL_MACHINE` `Path` value.

All the required sources are downloaded automatically
and all command tools and environment toolchains are installed using `pacman`.

### CLI help

Run `./ffmpeg-makexe.sh -h` for command-line usage and options:

```
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
    -n do not patch in xfade-easing, just build vanilla FFmpeg instead
    -r rebuild from scratch (removes cached downloads and build trees)
    -d <flags> set debug flags (e.g. -d SL):
       S trace shell command execution (set -x)
       M trace makefile recipe execution (--debug=print)
       L enable logging to ./ffmpeg-makexe-<environment>.log
       T use ./tmp/ for temporary files and keep them on exit
    -h print this message

See https://github.com/scriptituk/ffmpeg-makexe for more information
See https://github.com/scriptituk/msys2-mcvars used to ingest MSVC environment
See https://github.com/scriptituk/xfade-easing for xfade-easing usage
```

### Release

The version built is the latest FFmpeg release supported by pacman.
This is because external library dependencies work with that release but may not work with earlier releases.
The static build will almost certainly work however, so perhaps that should be an option.

### xfade-easing

You can switch [xfade-easing] support in or out with the `-n` option.
This does not cause `configure` to re-run; it just re-compiles `libavfilter/vf_xfade.c` and re-installs.
So for a plain FFmpeg build, run `./ffmpeg-makexe.sh -n`.

## Details

There are two versions: a static ffmpeg.exe and a [7-zip](https://www.7-zip.org/) archive containing ffmpeg.exe and dependent DLLs,
both include the [ffprobe] utility.

### Static Visual Studio builds

The MSYS environment builds a minimal static ffmpeg.exe with x264 encoding and zlib for PNG decoding based on [Roxlu’s guide](https://www.roxlu.com/2019/062/compiling-ffmpeg-with-x264-on-windows-10-using-msvc).

It executes the Visual Studio `vcvarsall.bat` script to ingest the MSVC development environment using [msys2-vcvars].

If more than one instance of `vcvarsall.bat` is found then set `VCVARSALL_PATH` to the absolute path (Windows or Unix format)
of the required instance.

To compile with LLVM `clang-cl` instead of MSVC `cl`, use option `-l`.

#### Static binaries

The built executables `ffmpeg.exe` and `ffprobe.exe` and install script `install-ffmpeg.bat` are at:

- `/opt/scriptituk/clangcl/dist/` for LLVM/clang-cl (option `-l`)\
  = `C:\msys64\opt\scriptituk\clangcl\dist\` from Windows
- `/opt/scriptituk/msvc/dist/` for MSVC\
  = `C:\msys64\opt\scriptituk\msvc\dist\` from Windows

#### Static installer

This is `install-ffmpeg.bat` for MSVC; only the source path differs.

```
@if exist "C:\Program Files\FFmpeg" del /q "C:\Program Files\FFmpeg"
xcopy C:\msys64\opt\scriptituk\msvc\dist\ff*.exe "C:\Program Files\FFmpeg\" /y
@rem TODO: set HKLM Path without changing REG_EXPAND_SZ to REG_SZ type
@if "%Path%"=="%Path:C:\Program Files\FFmpeg;=%" set Path=%Path%;C:\Program Files\FFmpeg;
```

#### Static configuration

This is for MSVC; clang-cl has the same components.

```
configuration:
  --extra-version=scriptituk/ffmpeg-makexe --prefix=/opt/scriptituk/msvc
  --enable-static --disable-shared
  --target-os=win64 --arch=x86_64 --pkg-config-flags=--static
  --toolchain=msvc
  --extra-cflags='-utf-8 -MT -wd4090 -wd4101 -wd4113 -wd4114 -wd4133 -Wv:12'
  --disable-ffplay --disable-debug --disable-doc
  --enable-gpl --enable-libx264 --enable-zlib
```

### Shared clang/gcc builds

The CLANG64/UCRT64/etc. environments build a ffmpeg.7z archive containing ffmpeg.exe and all its constituent DLLs.
Requires [7-zip](https://www.7-zip.org/download.html) to extract.

#### GPU options

FFmpeg options that use GPU hardware acceleration can break configuration tests,
especially when building with virtualization tools or WSL pre- Windows 11.
These are disabled by default but option `-g` restores them.

#### Shared binaries

The built executables `ffmpeg.exe`, `ffprobe.exe` and shared DLLs are compressed into `ffmpeg.7z`.
That and the install script `install-ffmpeg.bat` are at:

- `/opt/scriptituk/clang64/dist/` for LLVM/Clang\
  = `C:\msys64\opt\scriptituk\clang64\dist\` from Windows
- `/opt/scriptituk/ucrt64/dist/` for gcc\
  = `C:\msys64\opt\scriptituk\ucrt64\dist\` from Windows

#### Shared installer

This is `install-ffmpeg.bat` for CLANG64; only the source path differs.

```
@where 7z 2> nul || ( echo "7z not found" & exit /b )
@if exist "C:\Program Files\FFmpeg" del /q "C:\Program Files\FFmpeg"
7z x C:\msys64\opt\scriptituk\clang64\dist\ffmpeg.7z -o"C:\Program Files"
@rem TODO: set HKLM Path without changing REG_EXPAND_SZ to REG_SZ type
@if "%Path%"=="%Path:C:\Program Files\FFmpeg;=%" set Path=%Path%;C:\Program Files\FFmpeg;
```

#### Shared configuration

This is for CLANG64; UCRT64 etc. have the same components.

```
configuration:
  --extra-version=scriptituk/ffmpeg-makexe
  --prefix=/opt/scriptituk/clang64 --shlibdir=/opt/scriptituk/clang64/so
  --target-os=mingw32 --arch=x86_64 --cc=clang --cxx=clang++
  --disable-static --enable-shared --disable-debug --disable-ffplay --disable-doc
  --enable-dxva2 --enable-d3d11va --enable-d3d12va --enable-frei0r --enable-gmp
  --enable-gnutls --enable-gpl --enable-iconv --enable-libaom --enable-libass
  --enable-libbluray --enable-libcaca --enable-libdav1d --enable-libfontconfig
  --enable-libfreetype --enable-libfribidi --enable-libgme --enable-libgsm
  --enable-libharfbuzz --enable-libjxl --enable-libmodplug --enable-libmp3lame
  --enable-libopencore_amrnb --enable-libopencore_amrwb --enable-libopenjpeg
  --enable-libopus --enable-librtmp --enable-libssh --enable-libsoxr
  --enable-libspeex --enable-libsrt --enable-libtheora --enable-libvidstab
  --enable-libvorbis --enable-libx264 --enable-libx265 --enable-libxvid
  --enable-libvpx --enable-libwebp --enable-libxml2 --enable-libzimg
  --enable-libzvbi --enable-openal --enable-pic --enable-runtime-cpudetect
  --enable-swresample --enable-version3 --enable-zlib --enable-libvpl
  --enable-liblc3 --enable-librav1e --enable-librsvg --enable-libsvtav1
  --enable-libshaderc
```

#### MSYS2 path

Running the shared-library ffmpeg from a MSYS2 terminal (not Windows Command) picks up the system executable and libraries, not the built ones,
so, modify the `$PATH`:\
`PATH=/opt/scriptituk/clang64/bin:/opt/scriptituk/clang64/so:$PATH ffmpeg.exe`\
(change `clang64` to `ucrt64` for the `gcc` build).

#### Static build

Attempts to make a statically linked build using package-installed external components failed as it is quite convoluted but this may be revisited.

## Performance

Here are empirical metrics for the time to make 5-second 720x576 videos of the xfade-easing [ported GLSL transitions](https://github.com/scriptituk/xfade-easing/blob/main/README.md#glsl-gallery) (currently 64).
The test was run on a VirtualBox Windows 10 client, so is slower than a native run.

| MSYS2 environment | build environment | build type | size (MB) | time (minutes) |
| :---------------: | :---------------: | :--------: | :-------: | :------------: |
| MSYS | msvc | static | 24.852 | 10:19 |
| MSYS | clangcl | static | 27.996 | 09:42 |
| UCRT64 | ucrt64 | shared| 169.155<sup>a</sup> | 10:48 |
| CLANG64 | clang64 | shared| 154.542<sup>a</sup> | 10:47 |
| MINGW64 | mingw64 | shared| 169.574<sup>a</sup> | 17:07 |
| – | cross<sup>b</sup> | static | 116.541 | 17:01 |

<sup>a</sup> size includes uncompressed package-installed external DLLs\
<sup>b</sup> cross compiled on Ubuntu by [ffmpeg-windows-build-helpers](https://github.com/rdp/ffmpeg-windows-build-helpers) 

## See also

- [scriptituk/xfade-easing](https://github.com/scriptituk/xfade-easing) – Easing and extensions for FFmpeg Xfade filter
- [scriptituk/msys2-vcvars](https://github.com/scriptituk/msys2-vcvars) – Import MSVC environment variables into Msys2
- [Msys2 Environments](https://www.msys2.org/docs/environments/) – environment for building, installing and running native Windows software
- [Visual Studio Community Edition](https://visualstudio.microsoft.com/vs/community/) – free Microsoft Visual Studio Community edition
- [ffmpeg-windows-build-helpers](https://github.com/rdp/ffmpeg-windows-build-helpers) – cross compiles Windows 32/64-bit FFmpeg tools and dependencies
- [media-autobuild_suite](https://github.com/m-ab-s/media-autobuild_suite) – Windows Batchscript, builds Mingw-w64/GCC FFmpeg and other media tools
- [MultimediaTools-mingw-w64](https://github.com/Warblefly/MultimediaTools-mingw-w64) – scripts to cross-compile multimedia tools, inc. FFmpeg, for Windows
- [Roxlu’s guide](https://www.roxlu.com/2019/062/compiling-ffmpeg-with-x264-on-windows-10-using-msvc) – Compiling FFmpeg with X264 on Windows 10 using MSVC

[msys2-vcvars]: https://github.com/scriptituk/msys2-vcvars
[ffmpeg-makexe.sh]: https://github.com/scriptituk/ffmpeg-makexe/blob/main/ffmpeg-makexe.sh
[msys2-vcvars.sh]: https://github.com/scriptituk/msys2-vcvars/blob/main/msys2-vcvars.sh
[xfade-easing]: https://github.com/scriptituk/xfade-easing
[ffprobe]: https://ffmpeg.org/ffprobe.html
