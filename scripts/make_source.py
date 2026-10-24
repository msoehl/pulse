"""Writes an AltStore/SideStore source (source.json) for the IPA built in CI.

The source is attached to every GitHub release, so its stable URL is
https://github.com/<repo>/releases/latest/download/source.json
"""

import datetime
import json
import os
import sys


def main() -> None:
    ipa_path = sys.argv[1]
    repo = os.environ["GITHUB_REPOSITORY"]
    tag = os.environ["TAG"]
    version = os.environ["VERSION"]
    build = os.environ["BUILD"]

    raw = f"https://raw.githubusercontent.com/{repo}/main"
    source = {
        "name": "Pulse",
        "identifier": "de.soehl.pulse.source",
        "subtitle": "Recovery, Schlaf und Belastung aus Apple Health",
        "iconURL": f"{raw}/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "website": f"https://github.com/{repo}",
        "apps": [
            {
                "name": "Pulse",
                "bundleIdentifier": "de.soehl.pulse",
                "developerName": "Moritz Söhl",
                "subtitle": "Recovery, Schlaf und Belastung",
                "localizedDescription": (
                    "Wertet Apple-Health-Daten aus: Recovery, Schlafbedarf, Belastung, "
                    "Trainingslast und Trends. Daten per Health-Export oder Kurzbefehl."
                ),
                "iconURL": f"{raw}/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
                "tintColor": "#17D966",
                "category": "lifestyle",
                "versions": [
                    {
                        "version": version,
                        "buildVersion": build,
                        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                        "localizedDescription": f"Build {build}",
                        "downloadURL": f"https://github.com/{repo}/releases/download/{tag}/Pulse.ipa",
                        "size": os.path.getsize(ipa_path),
                        "minOSVersion": "17.0",
                    }
                ],
                "appPermissions": {
                    "entitlements": [
                        "com.apple.developer.healthkit",
                        "com.apple.developer.healthkit.access",
                    ],
                    "privacy": {
                        "NSHealthShareUsageDescription": "Pulse liest Apple-Health-Daten für Recovery, Schlaf und Belastung.",
                        "NSHealthUpdateUsageDescription": "Pulse schreibt keine Daten in Apple Health.",
                    },
                },
            }
        ],
        "news": [],
    }
    json.dump(source, sys.stdout, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
