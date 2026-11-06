.PHONY: verify mac-build mac-tests simulator-seed
verify:
	./scripts/verify_linux.sh
mac-build:
	./scripts/generate_and_build_macos.sh
mac-tests:
	xcodegen generate --spec project.yml
	xcodebuild -project CleanSlate.xcodeproj -scheme CleanSlate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
simulator-seed:
	./scripts/seed_simulator.sh
