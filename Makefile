.PHONY: test coverage lint setup sign-deps dmg clean-dmg

BUILD_DIR = $(shell pwd)/.build
DMG_NAME = TalkFlow-$(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" TalkFlow/Info.plist 2>/dev/null || echo "1.0.0").dmg
MODEL_DIR = TalkFlow/Resources/sensevoice
MODEL_FILE = $(MODEL_DIR)/model_quant.onnx

# ── 签名 Homebrew dylib（消除 Team ID 冲突，测试/运行必需） ──
sign-deps:
	@if [ -f /opt/homebrew/opt/onnxruntime/lib/libonnxruntime.1.24.4.dylib ]; then \
		for lib in /opt/homebrew/opt/onnxruntime/lib/*.dylib \
		          /opt/homebrew/opt/onnx/lib/*.dylib \
		          /opt/homebrew/opt/protobuf/lib/*.dylib \
		          /opt/homebrew/opt/abseil/lib/*.dylib \
		          /opt/homebrew/opt/re2/lib/*.dylib; do \
			[ -f "$$lib" ] || continue; \
			codesign --force --sign - "$$lib" 2>/dev/null || true; \
		done; \
		echo "✅ Homebrew dylibs re-signed"; \
	fi

test: sign-deps
	xcodebuild test \
		-scheme TalkFlow \
		-destination 'platform=macOS' \
		-enableCodeCoverage YES

coverage:
	xcodebuild test \
		-scheme TalkFlow \
		-destination 'platform=macOS' \
		-enableCodeCoverage YES \
		-resultBundlePath /tmp/TalkFlow_coverage.xcresult \
		-quiet
	@echo "📊 Coverage:"
	@xcrun xccov view --report /tmp/TalkFlow_coverage.xcresult

lint:
	@echo "🔍 swiftlint not configured — add .swiftlint.yml to enable"

# ── 下载模型文件（跳过已存在） ──
setup:
	@if [ -f "$(MODEL_FILE)" ]; then \
		echo "✅ Model already downloaded"; \
	else \
		echo "⬇️  Downloading STT model..."; \
		bash scripts/download-stt-model.sh; \
	fi

# ── 编译 Release .app ──
.app: setup sign-deps
	@echo "🔨 Building Release..."
	xcodebuild build \
		-scheme TalkFlow \
		-configuration Release \
		-destination 'platform=macOS,arch=arm64' \
		-derivedDataPath $(BUILD_DIR) \
		ONLY_ACTIVE_ARCH=YES \
		-quiet
	@echo "📦 Bundling dylibs..."
	bash scripts/bundle-dylibs.sh $(BUILD_DIR)/Build/Products/Release/TalkFlow.app
	@echo "✅ .app ready"

# ── 打包 DMG ──
dmg: .app
	@echo "💿 Creating DMG..."
	@rm -rf $(BUILD_DIR)/dmg
	@mkdir -p $(BUILD_DIR)/dmg
	@cp -R $(BUILD_DIR)/Build/Products/Release/TalkFlow.app $(BUILD_DIR)/dmg/
	@ln -s /Applications $(BUILD_DIR)/dmg/Applications 2>/dev/null || true
	hdiutil create -volname TalkFlow \
		-srcfolder $(BUILD_DIR)/dmg \
		-ov -format UDZO \
		"$(DMG_NAME)"
	@echo "✅ $(DMG_NAME) ready"

clean-dmg:
	@rm -rf $(BUILD_DIR)/dmg $(BUILD_DIR) $(DMG_NAME) 2>/dev/null
	@echo "🧹 cleaned"
