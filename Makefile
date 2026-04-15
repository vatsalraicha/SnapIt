SWIFT = xcrun swiftc
SDK = $(shell xcrun --show-sdk-path)
BUILD_DIR = .build
APP_NAME = SnapIt
BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

SWIFT_FLAGS = -sdk $(SDK) \
	-target arm64-apple-macos13.0 \
	-O \
	-framework Cocoa \
	-framework Vision \
	-framework ScreenCaptureKit \
	-framework CoreImage \
	-framework QuartzCore \
	-framework Carbon \
	-import-objc-header /dev/null

SOURCES = $(shell find Sources -name '*.swift')

.PHONY: all clean bundle run

all: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): $(SOURCES) | $(BUILD_DIR)
	$(SWIFT) $(SWIFT_FLAGS) -o $@ $(SOURCES)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

bundle: $(BUILD_DIR)/$(APP_NAME)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(BUNDLE)/Contents/
	@echo "Built $(BUNDLE)"

run: $(BUILD_DIR)/$(APP_NAME)
	$(BUILD_DIR)/$(APP_NAME)

clean:
	rm -rf $(BUILD_DIR)
