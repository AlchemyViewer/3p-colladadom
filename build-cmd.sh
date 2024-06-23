#!/usr/bin/env bash

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

#execute build from top-level checkout
cd "$(dirname "$0")"
top="$(pwd)"
stage="$top/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# There are two version numbers mixed up in the code below: the collada
# version (e.g. 1.4, upstream from colladadom?) and the dom version (e.g. 2.3,
# the version number we associate with this package). Get versions from
# Makefile.
# e.g. colladaVersion := 1.4
collada_version="$(sed -n -E 's/^ *colladaVersion *:= *([0-9]+\.[0-9]+) *$/\1/p' \
                       "$top/Makefile")"
# remove embedded dots
collada_shortver="${collada_version//.}"

# e.g.
# domMajorVersion := 2
# domMinorVersion := 3
dom_major="$(sed -n -E 's/^ *domMajorVersion *:= *([0-9]+) *$/\1/p' "$top/Makefile")"
dom_minor="$(sed -n -E 's/^ *domMinorVersion *:= *([0-9]+) *$/\1/p' "$top/Makefile")"
dom_version="$dom_major.$dom_minor"
dom_shortver="$dom_major$dom_minor"
echo "${dom_version}.0" > "${stage}/VERSION.txt"

case "$AUTOBUILD_PLATFORM" in

    windows*)
        if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
        then
            buildarchextra=""
        else
            buildarchextra="-x64"
        fi
        case "$AUTOBUILD_VSVER" in
            "120")
                versub="vc12-${collada_version}"
                debugbuilddir="vc12$buildarchextra-${collada_version}-d"
                relbuilddir="vc12$buildarchextra-${collada_version}"
                ;;
            16*)
                versub="vc14-${collada_version}"
                debugbuilddir="vc14$buildarchextra-${collada_version}-d"
                relbuilddir="vc14$buildarchextra-${collada_version}"
                ;;
            17*)
                versub="vc14-${collada_version}"
                debugbuilddir="vc14$buildarchextra-${collada_version}-d"
                relbuilddir="vc14$buildarchextra-${collada_version}"
                ;;
            *)
                echo "Unknown AUTOBUILD_VSVER='$AUTOBUILD_VSVER'" 1>&2 ; exit 1
                ;;
        esac
        projdir="projects/$versub"

        # Debug Build
        msbuild.exe "$(cygpath -w "$projdir/dom.sln")"  -p:Configuration="Debug" -p:Platform="$AUTOBUILD_WIN_VSPLATFORM" 

        # conditionally run unit tests
        if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            "build/$debugbuilddir/domTest.exe" -all
        fi

        # stage the good bits
        mkdir -p "$stage"/lib/debug

        debuglibname="libcollada${collada_shortver}dom${dom_shortver}-sd"
        cp -a build/$debugbuilddir/$debuglibname.* "$stage"/lib/debug/

        # Release Build
        msbuild.exe "$(cygpath -w "$projdir/dom.sln")"  -p:Configuration="Release" -p:Platform="$AUTOBUILD_WIN_VSPLATFORM" 

        # conditionally run unit tests
        if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            "build/$relbuilddir/domTest.exe" -all
        fi

        # stage the good bits
        mkdir -p "$stage"/lib/release

        rellibname="libcollada${collada_shortver}dom${dom_shortver}-s"
        cp -a build/$relbuilddir/$rellibname.* "$stage"/lib/release/
    ;;

    darwin*)
        # Setup build flags
        C_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CFLAGS"
        C_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CFLAGS"
        CXX_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CXXFLAGS"
        CXX_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CXXFLAGS"
        LINK_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_LINKER"
        LINK_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_LINKER"

        # deploy target
        export MACOSX_DEPLOYMENT_TARGET=${LL_BUILD_DARWIN_BASE_DEPLOY_TARGET}

        libdir="$top/stage"

        mkdir -p "$libdir"/lib/release
        mkdir -p "$libdir"/release_x86
        mkdir -p "$libdir"/release_arm64

        make clean arch="x86_64" # Hide 'arch' env var

        make -j$AUTOBUILD_CPU_COUNT \
            conf=release \
            CFLAGS="$C_OPTS_X86" \
            CXXFLAGS="$CXX_OPTS_X86" \
            LDFLAGS="$LINK_OPTS_X86" \
            arch="x86_64" \
            printCommands=yes \
            printMessages=yes

        # conditionally run unit tests
        if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            "build/mac-${collada_version}/domTest" -all
        fi

        cp -a "build/mac-${collada_version}/libcollada${collada_shortver}dom.a" "$libdir"/release_x86/

        make clean arch="x86_64" # Hide 'arch' env var

        make -j$AUTOBUILD_CPU_COUNT \
            conf=release \
            CFLAGS="$C_OPTS_ARM64" \
            CXXFLAGS="$CXX_OPTS_ARM64" \
            LDFLAGS="$LINK_OPTS_ARM64" \
            arch="arm64" \
            printCommands=yes \
            printMessages=yes

        # conditionally run unit tests
        if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            "build/mac-${collada_version}/domTest" -all
        fi

        cp -a "build/mac-${collada_version}/libcollada${collada_shortver}dom.a" "$libdir"/release_arm64/

        make clean arch="arm64" # Hide 'arch' env var

        # create fat libraries
        lipo -create ${stage}/release_x86/libcollada${collada_shortver}dom.a ${stage}/release_arm64/libcollada${collada_shortver}dom.a -output ${stage}/lib/release/libcollada${collada_shortver}dom.a
    ;;

    linux*)
        # Linux build environment at Linden comes pre-polluted with stuff that can
        # seriously damage 3rd-party builds.  Environmental garbage you can expect
        # includes:
        #
        #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
        #    DISTCC_LOCATION            top            branch      CC
        #    DISTCC_HOSTS               build_name     suffix      CXX
        #    LSDISTCC_ARGS              repo           prefix      CFLAGS
        #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
        #
        # So, clear out bits that shouldn't affect our configure-directed build
        # but which do nonetheless.
        #
        unset DISTCC_HOSTS CFLAGS CPPFLAGS CXXFLAGS

        # Default target per --address-size
        opts_ld="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
        opts_c="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE_CFLAGS}"
        opts_cxx="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE_CXXFLAGS}"
        
        # Handle any deliberate platform targeting
        if [ -z "${TARGET_CPPFLAGS:-}" ]; then
            # Remove sysroot contamination from build environment
            unset CPPFLAGS
        else
            # Incorporate special pre-processing flags
            export CPPFLAGS="$TARGET_CPPFLAGS"
        fi

        libdir="$top/stage"

        mkdir -p "$libdir"/lib/

        make clean arch="$AUTOBUILD_CONFIGURE_ARCH" # Hide 'arch' env var

        make -j$AUTOBUILD_CPU_COUNT \
            conf=release \
            LDFLAGS="$opts_ld" \
            CFLAGS="$opts_c" \
            CXXFLAGS="$opts_cxx" \
            arch="$AUTOBUILD_CONFIGURE_ARCH"

        # conditionally run unit tests
        if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            "build/linux-${collada_version}/domTest" -all
        fi

        cp -a "build/linux-${collada_version}/libcollada${collada_shortver}dom.a" "$libdir"/lib/
    ;;
esac

mkdir -p stage/include/collada
cp -a include/* stage/include/collada

mkdir -p stage/LICENSES
cp -a LICENSE stage/LICENSES/collada.txt

## mkdir -p stage/LICENSES/collada-other
cp -a license/tinyxml-license.txt stage/LICENSES/tinyxml.txt
