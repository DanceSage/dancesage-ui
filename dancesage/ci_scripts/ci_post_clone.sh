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

# The pose model is gitignored (30 MB), so a cloud build would ship without it
# and pose detection would silently do nothing. Fetch Google's file and refuse
# to build if it is not the exact one the app was tuned on.
echo "--- fetching the MediaPipe pose model"
MODEL="$CI_PRIMARY_REPOSITORY_PATH/dancesage/dancesage/pose_landmarker_heavy.task"
curl -fsSL -o "$MODEL" \
  https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task
echo "64437af838a65d18e5ba7a0d39b465540069bc8aae8308de3e318aad31fcbc7b  $MODEL" | shasum -a 256 -c -

echo "--- ready: $(ls -d Pods >/dev/null 2>&1 && echo 'Pods present' || echo 'PODS MISSING')"
