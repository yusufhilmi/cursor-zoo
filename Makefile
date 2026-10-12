APP      := Cursor Zoo.app
BIN      := CursorZoo
CONFIG   := release
BUILDDIR := .build/$(CONFIG)
# The Xcode license has not been accepted on this machine; the Command Line
# Tools toolchain builds the same sources without it. Override if you prefer Xcode.
DEVELOPER_DIR ?= /Library/Developer/CommandLineTools
export DEVELOPER_DIR

.PHONY: all build app run stop clean

all: app

build:
	swift build -c $(CONFIG)

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BUILDDIR)/$(BIN)" "$(APP)/Contents/MacOS/$(BIN)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	# Ad-hoc signature: no Developer ID on this machine yet. Enough to run locally.
	codesign --force --sign - --timestamp=none "$(APP)"
	@echo "built $(APP)"

run: app
	@pkill -x $(BIN) || true
	open "$(APP)"

stop:
	@pkill -x $(BIN) || true

clean:
	rm -rf .build "$(APP)"
