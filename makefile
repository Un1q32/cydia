gxx := clang++ -target armv6-apple-ios2
ifdef debug
strip := true
else
ifeq ($(shell uname -s),Darwin)
strip := strip
else
strip := cctools-strip
endif
endif

flags :=
link :=
libs := 

dpkg := dpkg-deb --root-owner-group -Zgzip

sdk := $(shell pwd)/iossdk

flags += -F$(sdk)/System/Library/PrivateFrameworks
flags += -I. -isystem sysroot/var/usr/include -isystem sysroot/usr/include
flags += -fmessage-length=0
ifdef debug
flags += -g -Og
else
flags += -g0 -O2
endif
flags += -fvisibility=hidden
flags += -w

xflags :=
xflags += -fobjc-call-cxx-cdtors
xflags += -fvisibility-inlines-hidden
xflags += -stdlib=libstdc++
xflags += -std=c++03

link += -Lsysroot/usr/lib
link += -stdlib=libstdc++
ifneq ($(shell uname -s),Darwin)
link += -fuse-ld=ld64 -mlinker-version=955.13
endif

libs += -framework CoreFoundation
libs += -framework CoreGraphics
libs += -framework Foundation
libs += -framework GraphicsServices
libs += -framework IOKit
libs += -framework JavaScriptCore
libs += -framework QuartzCore
libs += -framework SpringBoardServices
libs += -framework SystemConfiguration
libs += -framework WebCore
libs += -framework WebKit

libs += -lapt-pkg
libs += -licucore

uikit := 
uikit += -framework UIKit

backrow := 
backrow += -FAppleTV -framework BackRow -framework AppleTV

version := $(shell ./version.sh)

cycc = $(gxx) -o $@ -isysroot $(sdk) -F{sysroot,}/Library/Frameworks

dirs := Menes CyteKit Cydia SDURLCache

code := $(foreach dir,$(dirs),$(wildcard $(foreach ext,h hpp c cpp m mm,$(dir)/*.$(ext))))
code := $(filter-out SDURLCache/SDURLCacheTests.m,$(code))
code += MobileCydia.mm Version.mm iPhonePrivate.h Cytore.hpp lookup3.c Sources.h Sources.mm

source := $(filter %.m,$(code)) $(filter %.mm,$(code))
source += $(filter %.c,$(code)) $(filter %.cpp,$(code))
header := $(filter %.h,$(code)) $(filter %.hpp,$(code))

object := $(source)
object := $(object:.c=.o)
object := $(object:.cpp=.o)
object := $(object:.m=.o)
object := $(object:.mm=.o)
object := $(object:%=Objects/%)

images := $(shell find MobileCydia.app/ -type f -name '*.png')
images := $(images:%=Images/%)

all: MobileCydia

clean:
	rm -f MobileCydia postinst
	rm -rf Objects/ Images/

Objects/%.o: %.c $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c -x c $<

Objects/%.o: %.m $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c $< $(flags)

Objects/%.o: %.mm $(header)
	@mkdir -p $(dir $@)
	@echo "[cycc] $<"
	@$(cycc) -c $< $(flags) $(xflags)

Objects/Version.o: Version.h

Images/%.png: %.png
	@mkdir -p $(dir $@)
	@echo "[pngc] $<"
	@./pngcrush.sh $< $@

sysroot: sysroot.sh
	@echo "Your ./sysroot/ is either missing or out of date. Please re-run sysroot.sh." 1>&2
	@echo 1>&2
	@exit 1

MobileCydia: sysroot $(object) entitlements.xml
	@echo "[link] $(object:Objects/%=%)"
	@$(cycc) $(filter %.o,$^) $(flags) $(link) $(libs) $(uikit)
	@mkdir -p bins
	@cp -a $@ bins/$@-$(version)
	@echo "[strp] $@"
	@$(strip) -no_uuid $@
	@echo "[sign] $@"
	@ldid -T0 -Sentitlements.xml $@ || { rm -f $@ && false; }

CydiaAppliance: CydiaAppliance.mm
	@echo "[link] $(filter %.mm,$^)"
	@$(cycc) $(filter %.mm,$^) $(flags) $(link) -bundle $(libs) $(backrow)

cfversion: cfversion.c
	@echo "[link] $(filter %.c,$^)"
	@$(cycc) $(filter %.c,$^) $(flags) $(link) -framework CoreFoundation
	@ldid -T0 -S $@

postinst: postinst.mm Sources.mm Sources.h CyteKit/stringWithUTF8Bytes.mm CyteKit/stringWithUTF8Bytes.h CyteKit/UCPlatform.h
	@echo "[link] $(filter %.mm,$^)"
	@$(cycc) $(filter %.mm,$^) $(flags) $(link) -framework CoreFoundation -framework Foundation -framework UIKit
	@ldid -T0 -S $@

debs/cydia_$(version)_iphoneos-arm.deb: MobileCydia preinst postinst cfversion $(images) $(shell find MobileCydia.app) cydia.control Library/firmware.sh Library/startup
	rm -rf _
	mkdir -p _/var/lib/cydia
	
	mkdir -p _/etc/apt
	cp -a Trusted.gpg _/etc/apt/trusted.gpg.d
	cp -a Sources.list _/etc/apt/sources.list.d
	
	mkdir -p _/usr/libexec
	cp -a Library _/usr/libexec/cydia
	cp -a cfversion _/usr/libexec/cydia
	ln -s /usr/bin/du _/usr/libexec/cydia
	
	mkdir -p _/System/Library
	cp -a LaunchDaemons _/System/Library/LaunchDaemons
	
	mkdir -p _/Applications
	cp -a MobileCydia.app _/Applications/Cydia.app
	cp -a MobileCydia _/Applications/Cydia.app/MobileCydia
	
	cd MobileCydia.app && find . -name '*.png' -exec cp -af ../Images/MobileCydia.app/{} ../_/Applications/Cydia.app/{} ';'
	
	mkdir -p _/Applications/Cydia.app/Sources
	ln -s /usr/share/bigboss/icons/bigboss.png _/Applications/Cydia.app/Sources/apt.bigboss.us.com.png
	ln -s /usr/share/bigboss/icons/planetiphones.png _/Applications/Cydia.app/Sections/"Planet-iPhones Mods.png"
	
	mkdir -p _/DEBIAN
	./control.sh cydia.control _ >_/DEBIAN/control
	cp -a preinst postinst _/DEBIAN/
	
	chmod 6755 _/Applications/Cydia.app/MobileCydia

	find _ -name .DS_Store -delete
	
	mkdir -p debs
	ln -sf debs/cydia_$(version)_iphoneos-arm.deb Cydia.deb
	$(dpkg) -b _ Cydia.deb
	@echo "$$(ls -l $$(readlink Cydia.deb) | awk '{print $$5}') $$(readlink Cydia.deb)"

package: debs/cydia_$(version)_iphoneos-arm.deb

.PHONY: all clean package
