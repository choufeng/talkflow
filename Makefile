.PHONY: test coverage lint

test:
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
