#!/usr/bin/env python3
"""Render Resources/ReleaseNotes.json for one version.

The same entry the app shows in its What's New window becomes the appcast description
Sparkle displays before installing, and the body of the GitHub release. Written once,
published three ways.

    release-notes.py <version> --format html      # appcast <description>
    release-notes.py <version> --format markdown  # GitHub release body

Exits non-zero when the version has no entry, which is what stops release.sh from
publishing a release nobody wrote notes for.
"""

import argparse
import html
import json
import pathlib
import sys

NOTES = pathlib.Path(__file__).resolve().parent.parent / "Resources" / "ReleaseNotes.json"


def entry_for(version):
    try:
        document = json.loads(NOTES.read_text())
    except (OSError, ValueError) as error:
        sys.exit(f"error: could not read {NOTES}: {error}")

    for candidate in document.get("versions", []):
        if candidate.get("version") == version:
            return candidate
    sys.exit(
        f"error: {NOTES.name} has no entry for {version}.\n"
        f"       Add one before releasing — it is what the What's New window, the\n"
        f"       update prompt, and the release page all show."
    )


def as_html(entry):
    lines = []
    if entry.get("headline"):
        lines.append(f"<p>{html.escape(entry['headline'])}</p>")
    lines.append("<ul>")
    for highlight in entry.get("highlights", []):
        title = html.escape(highlight["title"])
        detail = html.escape(highlight["detail"])
        lines.append(f"  <li><b>{title}</b><br>{detail}</li>")
    lines.append("</ul>")
    return "\n".join(lines)


def as_markdown(entry):
    lines = []
    if entry.get("headline"):
        lines.append(entry["headline"])
        lines.append("")
    for highlight in entry.get("highlights", []):
        lines.append(f"**{highlight['title']}** — {highlight['detail']}")
        lines.append("")
    lines.append("Download `Perch.zip`, unzip, and drag Perch to /Applications.")
    lines.append("")
    lines.append(
        "Perch is signed and notarized by Apple, and requires macOS 14 or later. "
        "Smart Perch is included as an optional, entirely local feature."
    )
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--format", choices=["html", "markdown"], default="markdown")
    arguments = parser.parse_args()

    entry = entry_for(arguments.version)
    if not entry.get("highlights"):
        sys.exit(f"error: the {arguments.version} entry lists no highlights")

    if arguments.format == "html":
        print(as_html(entry))
    else:
        print(as_markdown(entry))


if __name__ == "__main__":
    main()
