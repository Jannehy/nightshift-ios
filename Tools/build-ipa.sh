#!/bin/bash
# Builds Nightshift.ipa. Run from the project root on a Mac with Xcode.
#
#   Tools/build-ipa.sh            -> build/Nightshift.ipa
#
# Fill in your Team ID in Tools/ExportOptions.plist first.
set -euo pipefail

SCHEME="Nightshift"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"

if grep -q REPLACE_WITH_TEAM_ID Tools/ExportOptions.plist; then
    echo "Set teamID in Tools/ExportOptions.plist first:" >&2
    echo "  grep -m1 DEVELOPMENT_TEAM $SCHEME.xcodeproj/project.pbxproj" >&2
    exit 1
fi

[ -d "$SCHEME.xcodeproj" ] || xcodegen generate

echo "==> Archiving"
xcodebuild archive \
    -project "$SCHEME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates

echo "==> Exporting"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist Tools/ExportOptions.plist \
    -exportPath "$BUILD_DIR" \
    -allowProvisioningUpdates

echo
ls -lh "$BUILD_DIR"/*.ipa
