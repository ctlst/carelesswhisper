APP_NAME := LocalWhisper
BUILD_DIR := .build/release
APP_DIR := $(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS := $(CONTENTS)/MacOS
RESOURCES := $(CONTENTS)/Resources
SWIFT_ENV := CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/module-cache
WHISPER_CPP_MODEL_URL := https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
WHISPER_CPP_MODEL := .models/whisper.cpp/ggml-base.en.bin
WHISPER_CPP_VERSION := v1.8.4
WHISPER_CPP_ARCHIVE := .build/vendor/whisper.cpp-$(WHISPER_CPP_VERSION).tar.gz
WHISPER_CPP_SRC := Vendor/whisper.cpp

.PHONY: setup setup-native vendor-whisper build-whisper build run clean app install

setup:
	python3 -m venv .venv
	.venv/bin/python3 -m pip install --upgrade pip
	.venv/bin/python3 -m pip install -r requirements.txt

setup-native:
	$(MAKE) vendor-whisper
	$(MAKE) build-whisper
	mkdir -p .models/whisper.cpp
	test -f "$(WHISPER_CPP_MODEL)" || curl -L "$(WHISPER_CPP_MODEL_URL)" -o "$(WHISPER_CPP_MODEL)"

vendor-whisper:
	test -d "$(WHISPER_CPP_SRC)" || (mkdir -p .build/vendor Vendor && curl -L "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/$(WHISPER_CPP_VERSION).tar.gz" -o "$(WHISPER_CPP_ARCHIVE)" && tar -xzf "$(WHISPER_CPP_ARCHIVE)" -C Vendor && mv "Vendor/whisper.cpp-$(WHISPER_CPP_VERSION:v%=%)" "$(WHISPER_CPP_SRC)")

build-whisper: vendor-whisper
	cmake -S "$(WHISPER_CPP_SRC)" -B "$(WHISPER_CPP_SRC)/build" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_SERVER=OFF -DGGML_METAL=OFF
	cmake --build "$(WHISPER_CPP_SRC)/build" --config Release -j

build:
	$(MAKE) build-whisper
	$(SWIFT_ENV) swift build -c release

run:
	$(SWIFT_ENV) swift run LocalWhisper

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS)" "$(RESOURCES)"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(MACOS)/$(APP_NAME)"
	cp Info.plist "$(CONTENTS)/Info.plist"
	cp Scripts/transcribe_file.py "$(RESOURCES)/transcribe_file.py"
	if [ "$${LOCALWHISPER_BUNDLE_PYTHON:-0}" = "1" ] && [ -d ".venv" ]; then cp -R ".venv" "$(RESOURCES)/.venv"; fi
	if [ "$${LOCALWHISPER_BUNDLE_PYTHON:-0}" = "1" ] && [ -d ".models/whisper" ]; then mkdir -p "$(RESOURCES)/.models"; cp -R ".models/whisper" "$(RESOURCES)/.models/whisper"; fi
	if [ -d ".models/whisper.cpp" ]; then mkdir -p "$(RESOURCES)/.models"; cp -R ".models/whisper.cpp" "$(RESOURCES)/.models/whisper.cpp"; fi
	chmod +x "$(RESOURCES)/transcribe_file.py"
	codesign --force --deep --sign - "$(APP_DIR)"

install: app
	rm -rf "/Applications/$(APP_DIR)"
	cp -R "$(APP_DIR)" /Applications/

clean:
	rm -rf .build "$(APP_DIR)"
