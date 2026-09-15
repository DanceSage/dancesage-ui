#!/bin/sh
# Xcode Cloud clones this repository and builds it exactly as it finds it, and it
# does not find Pods/ — that directory is gitignored, as it should be, with only
# Podfile and Podfile.lock committed. Without this the project points at
# Pods/Target Support Files/.../Pods-dancesage.release.xcconfig, which is not
# there, and the archive fails with "Unable to open base configuration reference
# file" before a line is compiled.
#
# Runs after the clone and before the build. CocoaPods is not on the Xcode Cloud
# image, so it is installed here.
set -e

echo "--- installing CocoaPods"
brew install cocoapods

echo "--- pod install"
cd "$CI_PRIMARY_REPOSITORY_PATH/dancesage"
pod install --repo-update

echo "--- ready: $(ls -d Pods >/dev/null 2>&1 && echo 'Pods present' || echo 'PODS MISSING')"
