SIM_ID = $(shell xcrun simctl list devices available | awk -F'[()]' '/iPhone/{print $$2; exit}')
PY := $(shell test -x .venv/bin/python && echo .venv/bin/python || echo python3)
DD := build/DerivedData
XCB := xcodebuild -project CleanSlate.xcodeproj -scheme CleanSlate -derivedDataPath $(DD) CODE_SIGNING_ALLOWED=NO

.PHONY: core-test gen build ios-test seed fixtures-test ci verify screens
core-test:
	swift test --package-path Core
gen:
	xcodegen generate --spec project.yml
build: gen
	$(XCB) -destination 'generic/platform=iOS Simulator' build
ios-test: gen
	@test -n "$(SIM_ID)" || { echo "No iPhone simulator available. Install one in Xcode > Settings > Components."; exit 2; }
	$(XCB) -destination "platform=iOS Simulator,id=$(SIM_ID)" test
fixtures-test:
	$(PY) -I -m unittest discover -s fixtures -p 'test_*.py'
seed:
	./scripts/seed_simulator.sh
ci: core-test fixtures-test build ios-test
verify:
	./scripts/verify_linux.sh

# Capture design-review screenshots (light, dark, large text) into docs/screens/<name>
screens:
	@test -n "$(SIM_ID)" || { echo "No iPhone simulator available."; exit 2; }
	TEST_RUNNER_CAPTURE_DIR=$(CURDIR)/docs/screens/$(or $(NAME),latest) $(XCB) -destination "platform=iOS Simulator,id=$(SIM_ID)" test -only-testing:CleanSlateUITests/ScreenshotTests
