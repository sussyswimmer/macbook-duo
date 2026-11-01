# Xcode is installed but the active developer dir is the Command Line Tools,
# so point xcodebuild at Xcode explicitly (no sudo xcode-select needed).
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Hinge.app

.PHONY: project build test run clean

project:
	xcodegen generate

build: project
	xcodebuild -project Hinge.xcodeproj -scheme Hinge -configuration Debug -derivedDataPath $(DERIVED) build

test: project
	xcodebuild -project Hinge.xcodeproj -scheme Hinge -derivedDataPath $(DERIVED) test

run: build
	-pkill -x Hinge
	open $(APP)

clean:
	rm -rf build Hinge.xcodeproj
