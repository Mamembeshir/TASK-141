#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# Environment check — iOS builds require macOS + Xcode.
# Exit 0 with an informational message when running inside a non-macOS
# environment (e.g. a Linux Docker container in CI) so the step is skipped
# cleanly rather than failing with a cryptic error.
# ---------------------------------------------------------------------------
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  SKIP — non-macOS environment detected (OS: $OS)"
    echo "│  GreenGate is an iOS project. Xcode and the iOS Simulator   │"
    echo "│  are only available on macOS runners.                       │"
    echo "│  Re-run this script on a macOS host to execute the suite.   │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    exit 0
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│  SKIP — xcodebuild not found                                │"
    echo "│  Install Xcode from the Mac App Store, then re-run.        │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    exit 0
fi

echo "GreenGate Test Suite"
DEST='platform=iOS Simulator,name=iPhone 16 Pro'
PROJECT='GreenGate.xcodeproj'
SCHEME='GreenGate'

RUN_UNIT=false
RUN_INT=false
RUN_VIEWS=false

if [ $# -eq 0 ]; then
    RUN_UNIT=true
    RUN_INT=true
    RUN_VIEWS=true
fi

for arg in "$@"; do
    case $arg in
        --unit)        RUN_UNIT=true ;;
        --integration) RUN_INT=true ;;
        --views)       RUN_VIEWS=true ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--unit] [--integration] [--views]"
            exit 1
            ;;
    esac
done

EXIT=0

if $RUN_UNIT; then
    echo "--- Unit Tests ---"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" \
        -only-testing:GreenGateTests/UnitTests test 2>&1 | (command -v xcpretty >/dev/null && xcpretty || cat) || EXIT=1
fi

if $RUN_INT; then
    echo "--- Integration Tests ---"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" \
        -only-testing:GreenGateTests/IntegrationTests test 2>&1 | (command -v xcpretty >/dev/null && xcpretty || cat) || EXIT=1
fi

if $RUN_VIEWS; then
    echo "--- View Tests ---"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DEST" \
        -only-testing:GreenGateTests/ViewTests test 2>&1 | (command -v xcpretty >/dev/null && xcpretty || cat) || EXIT=1
fi

exit $EXIT
