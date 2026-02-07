.PHONY: build release run clean install xcode-build xcode-release

APP_BUNDLE = build/ClawK.app
CONTENTS = $(APP_BUNDLE)/Contents
XCODE_BUILD_DIR = build/xcode

# Check if Xcode is available
XCODE_AVAILABLE := $(shell xcode-select -p 2>/dev/null | grep -q "Xcode.app" && echo "yes" || echo "no")

# Build debug version (SwiftPM - no widgets)
build:
	swift build
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/debug/ClawK $(CONTENTS)/MacOS/
	cp -R .build/debug/ClawK_ClawK.bundle $(CONTENTS)/Resources/ 2>/dev/null || true
	cp ClawK/Info.plist $(CONTENTS)/Info.plist
	@echo "APPL????" > $(CONTENTS)/PkgInfo
	@echo "✓ Built with SwiftPM (without widgets)"
	@echo "  Note: Install Xcode and run 'make xcode-build' for widget support"

# Build release version (SwiftPM - no widgets)
release:
	swift build -c release
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp .build/release/ClawK $(CONTENTS)/MacOS/
	cp -R .build/release/ClawK_ClawK.bundle $(CONTENTS)/Resources/ 2>/dev/null || true
	cp ClawK/Info.plist $(CONTENTS)/Info.plist
	@echo "APPL????" > $(CONTENTS)/PkgInfo

# Build with Xcode (includes widgets)
xcode-build:
ifeq ($(XCODE_AVAILABLE),yes)
	@echo "Building with Xcode (includes widgets)..."
	xcodebuild -project ClawK.xcodeproj -scheme ClawK -configuration Debug \
		-derivedDataPath $(XCODE_BUILD_DIR) build
	@killall ClawK 2>/dev/null || true
	@cp -R $(XCODE_BUILD_DIR)/Build/Products/Debug/ClawK.app /Applications/
	@echo "✓ Built with Xcode (with widgets)"
	@echo "✓ Installed to /Applications/ClawK.app"
else
	@echo "❌ Xcode not available. Using SwiftPM build instead."
	@$(MAKE) build
endif

# Build release with Xcode (includes widgets)
xcode-release:
ifeq ($(XCODE_AVAILABLE),yes)
	@echo "Building release with Xcode (includes widgets)..."
	xcodebuild -project ClawK.xcodeproj -scheme ClawK -configuration Release \
		-derivedDataPath $(XCODE_BUILD_DIR) build
	@echo "✓ Built release with Xcode (with widgets)"
else
	@echo "❌ Xcode not available. Using SwiftPM release build instead."
	@$(MAKE) release
endif

# Generate Xcode project (requires xcodegen)
generate-xcodeproj:
	@which xcodegen > /dev/null || (echo "Installing xcodegen..." && brew install xcodegen)
	xcodegen generate
	@echo "✓ Generated ClawK.xcodeproj"

# Run the app
run:
ifeq ($(XCODE_AVAILABLE),yes)
	@$(MAKE) xcode-build
	@open /Applications/ClawK.app
else
	@$(MAKE) build
	@open $(APP_BUNDLE)
endif

# Run release version
run-release: release
	open $(APP_BUNDLE)

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build build

# Install to /Applications
install: release
	cp -R $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/ClawK.app"

# Kill running instances
kill:
	@killall ClawK 2>/dev/null || echo "No running instance"

# Install UMAP dependencies for 3D visualization
install-umap:
	@echo "Setting up Python virtual environment for UMAP..."
	@cd ~/.openclaw/workspace && python3 -m venv .venv
	@cd ~/.openclaw/workspace && source .venv/bin/activate && pip install --quiet umap-learn numpy
	@echo "UMAP dependencies installed!"
	@echo "Memory 3D visualization will now use UMAP for better clustering."

# Full install with UMAP
install-full: release install-umap install
	@echo ""
	@echo "✅ ClawK.app installed with full UMAP support!"
	@echo "   Open from /Applications/ClawK.app or search in Spotlight"

# Show widget build status
widget-status:
ifeq ($(XCODE_AVAILABLE),yes)
	@echo "✓ Xcode available - widgets can be built"
	@echo "  Run 'make xcode-build' to build with widgets"
else
	@echo "⚠ Xcode not installed - widgets unavailable"
	@echo "  Install Xcode from the App Store, then run:"
	@echo "    sudo xcode-select -s /Applications/Xcode.app"
	@echo "    make generate-xcodeproj"
	@echo "    make xcode-build"
endif
