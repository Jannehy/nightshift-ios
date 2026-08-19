#!/usr/bin/env python3
"""Build (or update) the AltStore source for Nightshift.

AltStore reads a JSON file over HTTPS and offers every app listed in it. The
file has to carry the exact byte size of the IPA, which is why this is a script
and not a hand-maintained file.

    Tools/make-altstore-source.py build/Nightshift.ipa 1.0.0 \
        --repo Jannehy/nightshift-ios

Publish the result (altstore.json) in the repository; users then add
    https://raw.githubusercontent.com/<repo>/main/altstore.json
as a source in AltStore or SideStore.
"""
import argparse
import datetime
import json
import pathlib
import plistlib
import zipfile

BUNDLE_ID = "com.jannehy.nightshift"
TINT = "FFB03A"

DESCRIPTION = (
    "A native client for a self-hosted Nightshift server. Paste a Spotify, "
    "SoundCloud or YouTube link and watch the download live, search the iTunes "
    "catalog and pull tracks or whole albums straight into your library, manage "
    "the playlists the nightly job keeps in sync, and run that job by hand when "
    "you do not want to wait for the night.\n\n"
    "Needs a Nightshift server (1.3 or newer recommended) reachable from the "
    "phone — on the local network or through a VPN."
)


def read_versions(ipa: pathlib.Path) -> tuple[str, str]:
    """CFBundleShortVersionString and CFBundleVersion from the app in the IPA."""
    with zipfile.ZipFile(ipa) as archive:
        names = [n for n in archive.namelist()
                 if n.startswith("Payload/") and n.endswith(".app/Info.plist")
                 and n.count("/") == 2]
        if not names:
            raise SystemExit(f"no app Info.plist inside {ipa}")
        info = plistlib.loads(archive.read(names[0]))
    version = info.get("CFBundleShortVersionString")
    build = str(info.get("CFBundleVersion", "1"))
    if not version:
        raise SystemExit(f"no CFBundleShortVersionString in {names[0]}")
    return version, build


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=pathlib.Path, help="path to the built .ipa")
    parser.add_argument("--tag", help="release tag the IPA is attached to "
                                      "(default: v<version from the IPA>)")
    parser.add_argument("--repo", default="Jannehy/nightshift-ios",
                        help="GitHub owner/name the release lives in")
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path("altstore.json"))
    parser.add_argument("--min-os", default="16.0")
    parser.add_argument("--screenshots", type=pathlib.Path,
                        default=pathlib.Path("docs/screenshots"),
                        help="folder of PNG/JPG screenshots inside the repo")
    args = parser.parse_args()

    if not args.ipa.is_file():
        raise SystemExit(f"no such file: {args.ipa}")

    # Read the version out of the package instead of taking it on the command
    # line: AltStore refuses to install when the two disagree ("the downloaded
    # version does not match the version specified by the source"), and nobody
    # remembers whether the project says 1.0 or 1.0.0.
    version, build = read_versions(args.ipa)
    tag = args.tag or f"v{version}"

    base = f"https://github.com/{args.repo}"
    raw = f"https://raw.githubusercontent.com/{args.repo}/main"
    entry = {
        "version": version,
        "buildVersion": build,
        "date": datetime.date.today().isoformat(),
        "localizedDescription": f"Nightshift {version}.",
        "downloadURL": f"{base}/releases/download/{tag}/Nightshift.ipa",
        "size": args.ipa.stat().st_size,
        "minOSVersion": args.min_os,
    }

    # Keep older versions around so AltStore can offer a downgrade.
    versions = [entry]
    if args.out.exists():
        previous = json.loads(args.out.read_text())
        old = previous.get("apps", [{}])[0].get("versions", [])
        versions += [v for v in old if v.get("version") != version]

    # Screenshots are served straight out of the repository, so adding one is
    # a matter of dropping a file in and re-running this.
    shots = []
    if args.screenshots.is_dir():
        for shot in sorted(args.screenshots.iterdir()):
            if shot.suffix.lower() in (".png", ".jpg", ".jpeg"):
                shots.append(f"{raw}/{shot.as_posix()}")

    source = {
        "name": "Nightshift",
        "identifier": f"{BUNDLE_ID}.source",
        "subtitle": "Your music library's night shift",
        "website": base,
        "iconURL": f"{raw}/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
        "tintColor": TINT,
        "apps": [
            {
                "name": "Nightshift",
                "bundleIdentifier": BUNDLE_ID,
                "developerName": "Jannehy",
                "subtitle": "Client for a self-hosted Nightshift server",
                "localizedDescription": DESCRIPTION,
                "iconURL": f"{raw}/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
                "tintColor": TINT,
                "category": "utilities",
                # AltStore renamed this key between major versions; writing both
                # keeps old and new clients happy, and unknown keys are ignored.
                "screenshotURLs": shots,
                "screenshots": shots,
                "versions": versions,
            }
        ],
        "news": [],
    }

    args.out.write_text(json.dumps(source, indent=2) + "\n")
    size_mb = entry["size"] / 1024 / 1024
    print(f"wrote {args.out} — version {version} (build {build}), "
          f"{size_mb:.1f} MB, {len(shots)} screenshot(s)")
    print(f"download:   {entry['downloadURL']}")
    print(f"source URL: {raw}/{args.out.name}")


if __name__ == "__main__":
    main()
