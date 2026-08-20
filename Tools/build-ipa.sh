#!/bin/bash
# Builds Nightshift.ipa. Run from the project root on a Mac with Xcode.
#
#   Tools/build-ipa.sh                 -> build/Nightshift.ipa
#   TEAM_ID=ABCDE12345 Tools/build-ipa.sh
#
# The Team ID is read from the Xcode project, so it does not have to be written
# into a file that ends up in the repository. Set TEAM_ID to override.
set -euo pipefail

SCHEME="Nightshift"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"

# xcodebuild needs Xcode itself, not the Command Line Tools. Apple's own error
# for this names the cause but not the cure.
if ! xcodebuild -version >/dev/null 2>&1; then
    cat >&2 <<'MSG'
xcodebuild is not usable. If the error above mentions a "command line tools
instance", point the toolchain at Xcode:

    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
    xcodebuild -version
MSG
    exit 1
fi

[ -d "$SCHEME.xcodeproj" ] || xcodegen generate

TEAM="${TEAM_ID:-}"
if [ -z "$TEAM" ]; then
    TEAM=$(grep -m1 -o 'DEVELOPMENT_TEAM = [A-Z0-9]*' "$SCHEME.xcodeproj/project.pbxproj" \
           | awk '{print $3}' || true)
fi
if [ -z "$TEAM" ]; then
    cat >&2 <<'MSG'
No Team ID found.

Open the project in Xcode once and pick your team under Signing & Capabilities,
or put it into project.yml as DEVELOPMENT_TEAM so it survives regeneration, or
pass it in:

    TEAM_ID=ABCDE12345 Tools/build-ipa.sh

You will find it at developer.apple.com under Account -> Membership details.
MSG
    exit 1
fi
echo "==> Team $TEAM"

# The export options are templated: the checked-in file keeps the placeholder,
# the copy handed to xcodebuild carries the real ID.
OPTIONS=$(mktemp -t nightshift-export).plist
trap 'rm -f "$OPTIONS"' EXIT
sed "s/REPLACE_WITH_TEAM_ID/$TEAM/" Tools/ExportOptions.plist > "$OPTIONS"

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
    -exportOptionsPlist "$OPTIONS" \
    -exportPath "$BUILD_DIR" \
    -allowProvisioningUpdates

echo
ls -lh "$BUILD_DIR"/*.ipa
echo
echo "Next: Tools/make-altstore-source.py $BUILD_DIR/Nightshift.ipa"
