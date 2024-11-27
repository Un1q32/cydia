#!/usr/bin/env bash

if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    echo "bash 4.0 or newer required. Please read compiling.txt." 1>&2
    exit 1
fi

set -o pipefail
set -e

shopt -s extglob
shopt -s nullglob

for command in unlzma wget; do
    if ! which "${command}" &>/dev/null; then
        echo "Cannot run \`${command}\`. Please read compiling.txt." 1>&2
        exit 1
    fi
done

if gtar --help | grep bsdtar &>/dev/null; then
    echo "Running \`gtar\` is bsdtar :(. Please read compiling.txt." 1>&2
    exit 1
fi

wget -O iossdk.tar.lzma "https://invoxiplaygames.uk/sdks/iPhoneOS3.0.sdk.tar.lzma"
tar -xf iossdk.tar.lzma
mv iPhoneOS*.sdk iossdk
wget -O macsdk.tar.xz "https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.6.sdk.tar.xz"
tar -xf macsdk.tar.xz
mv MacOS*.sdk macsdk
macsdk="$PWD/macsdk"
rm macsdk.tar.xz iossdk.tar.lzma
rm -rf sysroot
mkdir sysroot
cd sysroot

repository=http://apt.saurik.com/
distribution=tangelo
component=main
architecture=iphoneos-arm

declare -A dpkgz
dpkgz[gz]=gunzip
dpkgz[lzma]=unlzma

function extract() {
    package=$1
    url=$2

    wget -O "${package}.deb" "${url}"
    for z in lzma gz; do
        compressed=data.tar.${z}

        if ar -x "${package}.deb" "${compressed}" 2>/dev/null; then
            ${dpkgz[${z}]} "${compressed}"
            break
        fi
    done

    if ! [[ -e data.tar ]]; then
        echo "unable to extract package" 1>&2
        exit 1
    fi

    ls -la data.tar
    gtar -xf ./data.tar
    rm -f data.tar
}

declare -A urls

urls[apr]=http://apt.saurik.com/debs/apr_1.3.3-4_iphoneos-arm.deb
urls[apr-lib]=http://apt.saurik.com/debs/apr-lib_1.3.3-2_iphoneos-arm.deb
urls[apt7]=http://apt.saurik.com/debs/apt7_0.7.25.3-9_iphoneos-arm.deb
urls[apt7-lib]=http://apt.saurik.com/debs/apt7-lib_0.7.25.3-16_iphoneos-arm.deb
urls[coreutils]=http://apt.saurik.com/debs/coreutils_8.12-13_iphoneos-arm.deb
urls[mobilesubstrate]=http://apt.saurik.com/debs/mobilesubstrate_0.9.6301_iphoneos-arm.deb
urls[pcre]=http://apt.saurik.com/debs/pcre_8.30-6_iphoneos-arm.deb

if [[ 0 ]]; then
    wget -qO- "${repository}dists/${distribution}/${component}/binary-${architecture}/Packages.bz2" | bzcat | {
        regex='^([^ \t]*): *(.*)'
        declare -A fields

        while IFS= read -r line; do
            if [[ ${line} == '' ]]; then
                package=${fields[package]}
                if [[ -n ${urls[${package}]} ]]; then
                    filename=${fields[filename]}
                    urls[${package}]=${repository}${filename}
                fi

                unset fields
                declare -A fields
            elif [[ ${line} =~ ${regex} ]]; then
                name=${BASH_REMATCH[1],,}
                value=${BASH_REMATCH[2]}
                fields[${name}]=${value}
            fi
        done
    }
fi

for package in "${!urls[@]}"; do
    extract "${package}" "${urls[${package}]}"
done

rm -f ./*.deb

if substrate=$(readlink usr/include/substrate.h); then
    if [[ ${substrate} == /* ]]; then
        ln -sf "../..${substrate}" usr/include/substrate.h
    fi
fi

mkdir -p usr/include
cd usr/include

mkdir CoreFoundation
wget -O CoreFoundation/CFBundlePriv.h "https://raw.githubusercontent.com/apple-oss-distributions/CF/refs/tags/CF-550/CFBundlePriv.h"
wget -O CoreFoundation/CFPriv.h "https://raw.githubusercontent.com/apple-oss-distributions/CF/refs/tags/CF-550/CFPriv.h"
wget -O CoreFoundation/CFUniChar.h "https://raw.githubusercontent.com/apple-oss-distributions/CF/refs/tags/CF-550/CFUniChar.h"

if true; then
    mkdir -p WebCore
    wget -O WebCore/WebCoreThread.h 'https://raw.githubusercontent.com/apple-oss-distributions/WebCore/refs/tags/WebCore-658.28/wak/WebCoreThread.h'
    wget -O WebCore/WebEvent.h 'https://raw.githubusercontent.com/apple-oss-distributions/WebCore/refs/tags/WebCore-658.28/platform/iphone/WebEvent.h'
else
    wget -O WebCore.tgz https://github.com/apple-oss-distributions/WebCore/archive/refs/tags/WebCore-658.28.tar.gz
    gtar -zx --transform 's@^[^/]*/@WebCore.d/@' -f WebCore.tgz

    mkdir WebCore
    cp -a WebCore.d/{*,rendering/style,platform/graphics/transforms}/*.h WebCore
    cp -a WebCore.d/platform/{animation,graphics,network,text}/*.h WebCore
    cp -a WebCore.d/{accessibility,platform{,/{graphics,network,text}}}/{cf,mac,iphone}/*.h WebCore
    cp -a WebCore.d/bridge/objc/*.h WebCore

    wget -O JavaScriptCore.tgz https://github.com/apple-oss-distributions/JavaScriptCore/archive/refs/tags/JavaScriptCore-554.1.tar.gz
    #gtar -zx --transform 's@^[^/]*/API/@JavaScriptCore/@' -f JavaScriptCore.tgz $(gtar -ztf JavaScriptCore.tgz | grep '/API/[^/]*.h$')
    gtar -zx \
        --transform 's@^[^/]*/@@' \
        --transform 's@^icu/@@' \
    -f JavaScriptCore.tgz $(gtar -ztf JavaScriptCore.tgz | sed -e '
        /\/icu\/unicode\/.*\.h$/ p;
        /\/profiler\/.*\.h$/ p;
        /\/runtime\/.*\.h$/ p;
        /\/wtf\/.*\.h$/ p;
        d;
    ')
fi

for framework in ApplicationServices CoreServices IOKit IOSurface JavaScriptCore WebKit; do
    ln -s "${macsdk}"/System/Library/Frameworks/"${framework}".framework/Headers "${framework}"
done

for framework in "${macsdk}"/System/Library/Frameworks/CoreServices.framework/Frameworks/*.framework; do
    name=${framework}
    name=${name%.framework}
    name=${name##*/}
    ln -s "${framework}/Headers" "${name}"
done

mkdir -p Cocoa
cat >Cocoa/Cocoa.h <<EOF
#define NSImage UIImage
#define NSView UIView
#define NSWindow UIWindow

#define NSPoint CGPoint
#define NSRect CGRect

#define NSPasteboard UIPasteboard
#define NSSelectionAffinity int
@protocol NSUserInterfaceValidations;
EOF

mkdir -p GraphicsServices
cat >GraphicsServices/GraphicsServices.h <<EOF
typedef struct __GSEvent *GSEventRef;
typedef struct __GSFont *GSFontRef;
EOF
