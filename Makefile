APP_NAME := CarelessWhisper
BUILD_DIR := .build/release
APP_DIR := $(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
SWIFT_ENV := CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/module-cache
APP_ICON := .build/CarelessWhisper.icns
WHISPER_CPP_MODEL_URL := https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
WHISPER_CPP_MODEL := .models/whisper.cpp/ggml-base.en.bin
WHISPER_CPP_VERSION := v1.8.4
WHISPER_CPP_ARCHIVE := .build/vendor/whisper.cpp-$(WHISPER_CPP_VERSION).tar.gz
WHISPER_CPP_SRC := Vendor/whisper.cpp

.PHONY: setup-native download-base-model vendor-whisper build-whisper app-icon build run clean app install

setup-native:
	$(MAKE) vendor-whisper
	$(MAKE) build-whisper

download-base-model:
	mkdir -p .models/whisper.cpp
	test -f "$(WHISPER_CPP_MODEL)" || curl -L "$(WHISPER_CPP_MODEL_URL)" -o "$(WHISPER_CPP_MODEL)"

vendor-whisper:
	test -d "$(WHISPER_CPP_SRC)" || (mkdir -p .build/vendor Vendor && curl -L "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/$(WHISPER_CPP_VERSION).tar.gz" -o "$(WHISPER_CPP_ARCHIVE)" && tar -xzf "$(WHISPER_CPP_ARCHIVE)" -C Vendor && mv "Vendor/whisper.cpp-$(WHISPER_CPP_VERSION:v%=%)" "$(WHISPER_CPP_SRC)")

build-whisper: vendor-whisper
	cmake -S "$(WHISPER_CPP_SRC)" -B "$(WHISPER_CPP_SRC)/build" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF -DGGML_METAL=OFF
	cmake --build "$(WHISPER_CPP_SRC)/build" --config Release -j

app-icon:
	$(SWIFT_ENV) swift Scripts/generate_app_icon.swift "$(APP_ICON)"

build:
	$(MAKE) build-whisper
	$(SWIFT_ENV) swift build -c release

run:
	$(MAKE) setup-native
	$(SWIFT_ENV) swift run CarelessWhisper

app: setup-native app-icon build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS)" "$(RESOURCES)"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(MACOS)/$(APP_NAME)"
	cp Info.plist "$(CONTENTS)/Info.plist"
	cp "$(APP_ICON)" "$(RESOURCES)/CarelessWhisper.icns"
	cp Assets/active.svg "$(RESOURCES)/active.svg"
	cp Assets/inactive.svg "$(RESOURCES)/inactive.svg"
	if [ -f "Assets/cat-sprite.png" ]; then cp Assets/cat-sprite.png "$(RESOURCES)/cat-sprite.png"; fi
	if [ "$(BUNDLE_MODELS)" = "1" ] && [ -d ".models/whisper.cpp" ]; then mkdir -p "$(RESOURCES)/.models"; cp -R ".models/whisper.cpp" "$(RESOURCES)/.models/whisper.cpp"; fi
	codesign --force --deep --sign - "$(APP_DIR)"

install: app
	rm -rf "/Applications/$(APP_DIR)"
	cp -R "$(APP_DIR)" /Applications/

clean:
	rm -rf .build "$(APP_DIR)"
