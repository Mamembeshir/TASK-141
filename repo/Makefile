SCHEME  = GreenGate
DEST    = platform=iOS Simulator,name=iPhone 16 Pro
PROJECT = GreenGate.xcodeproj

.PHONY: build test test-unit test-integration test-views clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' build

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' test

test-unit:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-only-testing:GreenGateTests/UnitTests test

test-integration:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-only-testing:GreenGateTests/IntegrationTests test

test-views:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-only-testing:GreenGateTests/ViewTests test

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
