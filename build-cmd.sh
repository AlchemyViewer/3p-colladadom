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

[ -f "$stage"/packages/include/zlib/zlib.h ] || \
{ echo "You haven't yet run autobuild install." 1>&2 ; exit 1; }

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
build=${AUTOBUILD_BUILD_ID:=0}
echo "${dom_version}.${build}" > "${stage}/VERSION.txt"

case "$AUTOBUILD_PLATFORM" in

    windows*)
        if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
        then
            buildarchextra=""
        else
            buildarchextra="-x64"
        fi
        case "$AUTOBUILD_WIN_VSVER" in
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
            *)
                echo "Unknown AUTOBUILD_WIN_VSVER='$AUTOBUILD_WIN_VSVER'" 1>&2 ; exit 1
                ;;
        esac
        projdir="projects/$versub"

        # Debug Build
        build_sln "$projdir/dom.sln" "Debug" "$AUTOBUILD_WIN_VSPLATFORM"

        # conditionally run unit tests
        if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            cp -a $stage/packages/lib/debug/*dll "build/$debugbuilddir/"
            "build/$debugbuilddir/domTest.exe" -all
        fi

        # stage the good bits
        mkdir -p "$stage"/lib/debug

        debuglibname="libcollada${collada_shortver}dom${dom_shortver}-d"
        cp -a build/$debugbuilddir/$debuglibname.* "$stage"/lib/debug/

        # Release Build
        build_sln "$projdir/dom.sln" "Release" "$AUTOBUILD_WIN_VSPLATFORM"

        # conditionally run unit tests
        if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            cp -a $stage/packages/lib/release/*dll "build/$relbuilddir/"
            "build/$relbuilddir/domTest.exe" -all
        fi

        # stage the good bits
        mkdir -p "$stage"/lib/release

        rellibname="libcollada${collada_shortver}dom${dom_shortver}"
        cp -a build/$relbuilddir/$rellibname.* "$stage"/lib/release/
    ;;

    darwin*)
        # Darwin build environment at Linden is also pre-polluted like Linux
        # and that affects colladadom builds.  Here are some of the env vars
        # to look out for:
        #
        # AUTOBUILD             GROUPS              LD_LIBRARY_PATH         SIGN
        # arch                  branch              build_*                 changeset
        # helper                here                prefix                  release
        # repo                  root                run_tests               suffix

        opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH -std=c++11 $LL_BUILD_RELEASE}"

        libdir="$top/stage"
        mkdir -p "$libdir"/lib/release

        make clean arch="$AUTOBUILD_CONFIGURE_ARCH" # Hide 'arch' env var

        # Without the -Wno-etc flag, incredible spam is produced
        make \
            conf=release \
            CFLAGS="$opts" \
            CXXFLAGS="$opts -Wno-unused-local-typedef" \
            LDFLAGS="-Wl,-headerpad_max_install_names" \
            arch="$AUTOBUILD_CONFIGURE_ARCH" \
            printCommands=yes \
            printMessages=yes

        # conditionally run unit tests
        if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            "build/mac-${collada_version}/domTest" -all
        fi

        # install_name_tool -id "@executable_path/../Resources/libcollada${collada_shortver}dom-d.dylib" "build/mac-${collada_version}-d/libcollada${collada_shortver}dom-d.dylib"
        # install_name_tool -id "@executable_path/../Resources/libcollada${collada_shortver}dom.dylib" "build/mac-${collada_version}/libcollada${collada_shortver}dom.dylib"

        cp -a "build/mac-${collada_version}/libcollada${collada_shortver}dom.a" "$libdir"/lib/release/
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
        # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

##      # Prefer gcc-4.6 if available.
##      if [ -x /usr/bin/gcc-4.6 -a -x /usr/bin/g++-4.6 ]; then
##          export CC=/usr/bin/gcc-4.6
##          export CXX=/usr/bin/g++-4.6
##      fi

        # Default target per --address-size
        opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
        DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC -DPIC"
        RELEASE_COMMON_FLAGS="$opts -O3 -g -fPIC -fstack-protector-strong -DPIC -D_FORTIFY_SOURCE=2"
        DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
        RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
        DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
        RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
        DEBUG_CPPFLAGS="-DPIC"
        RELEASE_CPPFLAGS="-DPIC -D_FORTIFY_SOURCE=2"
        
        JOBS=`cat /proc/cpuinfo | grep processor | wc -l`

        # Handle any deliberate platform targeting
        if [ -z "${TARGET_CPPFLAGS:-}" ]; then
            # Remove sysroot contamination from build environment
            unset CPPFLAGS
        else
            # Incorporate special pre-processing flags
            export CPPFLAGS="$TARGET_CPPFLAGS"
        fi

        libdir="$top/stage"

        mkdir -p "$libdir"/lib/debug

        make clean arch="$AUTOBUILD_CONFIGURE_ARCH" # Hide 'arch' env var

        make -j$JOBS \
            conf=debug \
            LDFLAGS="$opts" \
            CFLAGS="$DEBUG_CFLAGS" \
            CXXFLAGS="$DEBUG_CXXFLAGS" \
            arch="$AUTOBUILD_CONFIGURE_ARCH"

        # conditionally run unit tests
        if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            "build/linux-${collada_version}-d/domTest" -all
        fi

        cp -a "build/linux-${collada_version}-d/libcollada${collada_shortver}dom-d.a" "$libdir"/lib/debug/
    
        mkdir -p "$libdir"/lib/release

        make clean arch="$AUTOBUILD_CONFIGURE_ARCH" # Hide 'arch' env var

        make -j$JOBS \
            conf=release \
            LDFLAGS="$opts" \
            CFLAGS="$RELEASE_CFLAGS" \
            CXXFLAGS="$RELEASE_CXXFLAGS" \
            arch="$AUTOBUILD_CONFIGURE_ARCH"

        # conditionally run unit tests
        if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
            "build/linux-${collada_version}/domTest" -all
        fi

        cp -a "build/linux-${collada_version}/libcollada${collada_shortver}dom.a" "$libdir"/lib/release/
    ;;
esac

mkdir -p stage/include/collada
cp -a include/* stage/include/collada

mkdir -p stage/LICENSES
cp -a license.txt stage/LICENSES/collada.txt

## mkdir -p stage/LICENSES/collada-other
cp -a license/tinyxml-license.txt stage/LICENSES/tinyxml.txt

mkdir -p stage/docs/colladadom/
cp -a README.Linden stage/docs/colladadom/
