#!/bin/bash
# about: build the app (Debug, into DD/) and the package; nothing is launched.
# limit: 420
cd "$ROOT" || exit 2
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD \
  -destination 'platform=macOS,arch=arm64' build
