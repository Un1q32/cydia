#!/usr/bin/env bash

if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    echo "bash 4.0 or newer required." 1>&2
    exit 1
fi

shopt -s extglob
shopt -s nullglob

rm -rf iossdk macsdk
wget -O iossdk.tar.lzma 'https://invoxiplaygames.uk/sdks/iPhoneOS4.0.sdk.tar.lzma'
gtar -xf iossdk.tar.lzma
mv iPhoneOS*.sdk iossdk
wget -O macsdk.tar.xz 'https://github.com/phracker/MacOSX-SDKs/releases/download/11.3/MacOSX10.6.sdk.tar.xz'
gtar -xf macsdk.tar.xz
mv MacOS*.sdk macsdk
macsdk="$PWD/macsdk"
rm macsdk.tar.xz iossdk.tar.lzma

rm -rf sysroot
mkdir sysroot
cd sysroot || exit 1

repository=http://apt.saurik.com/
distribution=tangelo
component=main
architecture=iphoneos-arm

wget -qO- "${repository}dists/${distribution}/${component}/binary-${architecture}/Packages.bz2" | bzcat | {
    regex='^([^ \t]*): *(.*)'
    declare -A fields

    while IFS= read -r line; do
        if [[ ${line} == '' ]]; then
            package=${fields[package]}
            if [[ ${package} == *(apr|apr-lib|apt7|apt7-lib|coreutils|mobilesubstrate|pcre) ]]; then
                filename=${fields[filename]}
                wget -O "${package}.deb" "${repository}${filename}"
                dpkg-deb -x "${package}.deb" .
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

rm -f ./*.deb

mkdir -p usr/include
cd usr/include || exit 1

mkdir CoreFoundation
wget -O CoreFoundation/CFBundlePriv.h "https://raw.githubusercontent.com/apple-oss-distributions/CF/refs/tags/CF-550/CFBundlePriv.h"
wget -O CoreFoundation/CFPriv.h "https://raw.githubusercontent.com/apple-oss-distributions/CF/refs/tags/CF-550/CFPriv.h"
wget -O CoreFoundation/CFUniChar.h "https://raw.githubusercontent.com/apple-oss-distributions/CF/refs/tags/CF-550/CFUniChar.h"

mkdir -p WebCore
wget -O WebCore/WebCoreThread.h 'https://raw.githubusercontent.com/apple-oss-distributions/WebCore/refs/tags/WebCore-658.28/wak/WebCoreThread.h'

for framework in ApplicationServices CoreServices IOKit IOSurface JavaScriptCore QuartzCore WebKit; do
    ln -s "${macsdk}"/System/Library/Frameworks/"${framework}".framework/Headers "${framework}"
done

for framework in "${macsdk}"/System/Library/Frameworks/CoreServices.framework/Frameworks/*.framework; do
    name=${framework}
    name=${name%.framework}
    name=${name##*/}
    ln -s "${framework}/Headers" "${name}"
done

mkdir -p sys
ln -s "${macsdk}"/usr/include/sys/reboot.h sys
ln -sf ../../Library/Frameworks/CydiaSubstrate.framework/Headers/CydiaSubstrate.h substrate.h

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
