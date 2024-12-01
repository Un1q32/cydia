flags := 
link := 

dpkg := dpkg-deb -Zgzip --root-owner-group

sdk := iossdk

flags += -F$(sdk)/System/Library/PrivateFrameworks
flags += -I. -isystem sysroot/usr/include -Lsysroot/usr/lib
flags += -w
flags += -fmessage-length=0
flags += -g0 -O2
flags += -fobjc-call-cxx-cdtors -fobjc-exceptions

link += -framework CoreFoundation
link += -framework CoreGraphics
link += -framework Foundation
link += -framework GraphicsServices
link += -framework IOKit
link += -framework JavaScriptCore
link += -framework QuartzCore
link += -framework SpringBoardServices
link += -framework SystemConfiguration
link += -framework WebCore
link += -framework WebKit

link += -lapr-1
link += -lapt-pkg
link += -lpcre

uikit := 
uikit += -framework UIKit

gxx := clang++
cycc = $(gxx) -target armv6-apple-ios3 -o $@ -isysroot $(sdk) -stdlib=libstdc++ -std=c++03

all: MobileCydia

clean:
	rm -f MobileCydia

%.o: %.c
	$(cycc) -c -o $@ -x c $<

MobileCydia: MobileCydia.mm UICaboodle/*.h UICaboodle/*.mm SDURLCache/SDURLCache.h SDURLCache/SDURLCache.m iPhonePrivate.h lookup3.o Cytore.hpp
	$(cycc) $(filter %.mm,$^) $(filter %.o,$^) $(foreach m,$(filter %.m,$^),-x objective-c++ $(m)) $(flags) $(link) $(uikit)
	ldid -Slaunch.xml $@ || { rm -f $@ && false; }

CydiaAppliance: CydiaAppliance.mm
	$(cycc) $(filter %.mm,$^) $(flags) -bundle $(link) $(backrow)

package: MobileCydia
	rm -rf _
	mkdir -p _/var/lib/cydia
	
	mkdir -p _/usr/libexec
	cp -a Library _/usr/libexec/cydia
	cp -a sysroot/usr/bin/du _/usr/libexec/cydia
	
	mkdir -p _/System/Library
	cp -a LaunchDaemons _/System/Library/LaunchDaemons
	
	mkdir -p _/Applications
	cp -a MobileCydia.app _/Applications/Cydia.app
	cp -a MobileCydia _/Applications/Cydia.app/MobileCydia
	
	mkdir -p _/System/Library/PreferenceBundles
	cp -a CydiaSettings.bundle _/System/Library/PreferenceBundles/CydiaSettings.bundle
	
	mkdir -p _/DEBIAN
	./control.sh _ >_/DEBIAN/control
	
	find _ -name '*.png' -exec ./pngcrush.sh '{}' ';'
	
	chmod 6755 _/Applications/Cydia.app/MobileCydia
	
	mkdir -p debs
	ln -sf debs/cydia_$$(./version.sh)_iphoneos-arm.deb Cydia.deb
	$(dpkg) -b _ Cydia.deb
	@echo "$$(ls -l $$(readlink Cydia.deb) | awk '{print $$5}') $$(readlink Cydia.deb)"

.PHONY: all clean sign
