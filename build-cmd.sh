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

if [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" ]] ; then
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

# remove_cxxstd apply_patch
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

[ -f "$stage"/packages/include/minizip-ng/zip.h ] || \
{ echo "You haven't yet run autobuild install." 1>&2 ; exit 1; }

# Use msbuild.exe instead of devenv.com
build_sln() {
    local solution=$1
    local config=$2
    local proj="${3:-}"
    local toolset="${AUTOBUILD_WIN_VSTOOLSET:-v143}"

    # e.g. config = "Release|$AUTOBUILD_WIN_VSPLATFORM" per devenv.com convention
    local -a confparts
    IFS="|" read -ra confparts <<< "$config"

    msbuild.exe \
        "$(cygpath -w "$solution")" \
        ${proj:+-t:"$proj"} \
        -p:Configuration="${confparts[0]}" \
        -p:Platform="${confparts[1]}" \
        -p:PlatformToolset=$toolset
}

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

case "$AUTOBUILD_PLATFORM" in

    windows*)
        case "$AUTOBUILD_VSVER" in
            "120")
                versub="vc12-${collada_version}"
                ;;
            "150")
                versub="vc14-${collada_version}"
                ;;
            "160"|"170")
                versub="vc142-${collada_version}"
                ;;
            *)
                echo "Unknown AUTOBUILD_VSVER='$AUTOBUILD_VSVER'" 1>&2 ; exit 1
                ;;
        esac
        projdir="projects/$versub"

        for arch in sse avx2 arm64 ; do
            platform_target="x64"
            proj_suffix=""
            if [[ "$arch" == "avx2" ]]; then
                proj_suffix="_avx2"
            elif [[ "$arch" == "arm64" ]]; then
                platform_target="ARM64"
            fi


            build_sln "$projdir/dom.sln" "Debug$proj_suffix|$platform_target" dom
            build_sln "$projdir/dom.sln" "Debug$proj_suffix|$platform_target" dom-static
            build_sln "$projdir/dom.sln" "Debug$proj_suffix|$platform_target" domTest

            # conditionally run unit tests
            if [[ "${DISABLE_UNIT_TESTS:-0}" == "0" && "$arch" != "arm64" ]]; then
                if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
                    then
                        "build/$versub/domTest.exe" -all
                    else
                        # 64 bit exe ends up in different location to 32 bit hard coded
                        # path to data directory - source code suggests it looks in a dir
                        # called domTestData first so we make one
                        mkdir -p "$projdir/$platform_target/Debug$proj_suffix/domTestData"
                        cp "test/${collada_version}/data"/* "$projdir/$platform_target/Debug$proj_suffix/domTestData/"
                        "$projdir/$platform_target/Debug$proj_suffix/domTest.exe" -all
                fi
            fi

            # stage the good bits
            mkdir -p "$stage"/lib/$arch/debug

            libname="libcollada${collada_shortver}dom${dom_shortver}-sd.lib"
            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
                then cp -a "build/$versub/$libname" "$stage"/lib/$arch/debug/
                else cp -a "$projdir/$platform_target/Debug$proj_suffix/$libname" "$stage"/lib/$arch/debug/
            fi

            build_sln "$projdir/dom.sln" "Release$proj_suffix|$platform_target" dom
            build_sln "$projdir/dom.sln" "Release$proj_suffix|$platform_target" dom-static
            build_sln "$projdir/dom.sln" "Release$proj_suffix|$platform_target" domTest

            # conditionally run unit tests
            if [[ "${DISABLE_UNIT_TESTS:-0}" == "0" && "$arch" != "arm64" ]]; then
                if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
                    then
                        "build/$versub/domTest.exe" -all
                    else
                        # 64 bit exe ends up in different location to 32 bit hard coded
                        # path to data directory - source code suggests it looks in a dir
                        # called domTestData first so we make one
                        mkdir -p "$projdir/$platform_target/Release$proj_suffix/domTestData"
                        cp "test/${collada_version}/data"/* "$projdir/$platform_target/Release$proj_suffix/domTestData/"
                        "$projdir/$platform_target/Release$proj_suffix/domTest.exe" -all
                fi
            fi

            # stage the good bits
            mkdir -p "$stage"/lib/$arch/release

            libname="libcollada${collada_shortver}dom${dom_shortver}-s.lib"
            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
                then cp -a "build/$versub/$libname" "$stage"/lib/$arch/release/
                else cp -a "$projdir/$platform_target/Release/$libname" "$stage"/lib/$arch/release/
            fi
        done
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
        export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

        opts="${TARGET_OPTS:--arch arm64 -arch x86_64 $LL_BUILD_RELEASE}"

        nproc=$(sysctl -n hw.physicalcpu)

        libdir="$top/stage"
        mkdir -p "$libdir"/lib/release

        # Without the -Wno-etc flag, incredible spam is produced
        make \
            conf=release \
            -j$nproc \
            CFLAGS="$opts" \
            CXXFLAGS="$opts -Wno-unused-local-typedef" \
            LDFLAGS="-Wl,-headerpad_max_install_names" \
            arch="x86_64 arm64" \
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

    linux64)

        # Default target per --address-size
        opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

        # Handle any deliberate platform targeting
        if [ -z "${TARGET_CPPFLAGS:-}" ]; then
            # Remove sysroot contamination from build environment
            unset CPPFLAGS
        else
            # Incorporate special pre-processing flags
            export CPPFLAGS="$TARGET_CPPFLAGS"
        fi

        libdir="$top/stage"

        for arch in sse avx2 ; do
            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"
            if [[ "$arch" == "avx2" ]]; then
                opts="$(replace_switch -march=x86-64-v2 -march=x86-64-v3 $opts)"
            fi
            plainopts="$(remove_cxxstd $opts)"

            make clean arch="$arch" # Hide 'arch' env var

            make -j$AUTOBUILD_CPU_COUNT \
                conf=release \
                LDFLAGS="$opts" \
                CFLAGS="$plainopts" \
                CXXFLAGS="$opts" \
                arch="$arch"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                "build/linux-${collada_version}/domTest" -all
            fi

            mkdir -p "$libdir"/lib/$arch/release
            cp -a "build/linux-${collada_version}/libcollada${collada_shortver}dom.a" "$libdir"/lib/$arch/release/
        done
    ;;
esac

mkdir -p stage/include/collada
cp -a include/* stage/include/collada

mkdir -p stage/LICENSES
cp -a license.txt stage/LICENSES/collada.txt

## mkdir -p stage/LICENSES/collada-other
cp -a license/tinyxml-license.txt stage/LICENSES/tinyxml.txt
