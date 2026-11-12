PROJECT    := ModernMac.xcodeproj
SCHEME     := ModernMac
DERIVED    := .build/xcode
APP        := $(DERIVED)/Build/Products/Debug/ModernMac.app
BINARY     := $(APP)/Contents/MacOS/ModernMac
SUBSYSTEM  := com.ando.ModernMac
XCODEBUILD := xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
	-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=$(shell uname -m)'

.PHONY: gen build test run kill logs simulate snapshots

gen:
	xcodegen generate --quiet

build: gen
	$(XCODEBUILD) build

test: gen
	$(XCODEBUILD) test

run: build kill
	open $(APP)

# Stops the running copy and waits until it is really gone, so `open` in
# `make run` starts the new build instead of re-activating the old process.
kill:
	@pkill -x ModernMac || true
	@while pgrep -x ModernMac >/dev/null; do sleep 0.1; done

logs:
	log stream --level debug --predicate 'subsystem == "$(SUBSYSTEM)"'

# Usage: make simulate ARGS="kind=volume&level=0.6&style=tahoe"
simulate:
	open "modernmac://simulate?$(ARGS)"

snapshots: build
	$(BINARY) --snapshots .build/snapshots
