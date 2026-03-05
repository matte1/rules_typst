"""A script for fetching all available versions of Typst."""

import argparse
import base64
import binascii
import hashlib
import json
import logging
import os
import re
import time
import urllib.request
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import urlopen

# Chunk size for streaming downloads when computing integrity
DOWNLOAD_CHUNK_SIZE = 1 << 20  # 1 MiB

TYPST_GITHUB_RELEASES_API_TEMPLATE = (
    "https://api.github.com/repos/typst/typst/releases?page={page}"
)

TYPST_RELEASE_TAG_REGEX = r"^v(\d+\.\d+\.\d+)$"

# Asset names are typst-<platform>.tar.xz or typst-<platform>.zip
TYPST_ASSET_PREFIX = "typst-"
TYPST_ASSET_SUFFIXES = (".tar.xz", ".zip")

REQUEST_HEADERS = {"User-Agent": "curl/8.7.1"}  # Set the User-Agent header

BUILD_TEMPLATE = """\
\"\"\"Typst Versions

A mapping of platform to url and integrity of the archive for said platform for each version of Typst available.
\"\"\"

# AUTO-GENERATED: DO NOT MODIFY
#
# Update using the following command:
#
# ```
# bazel run //tools/update_versions
# ```

TYPST_VERSIONS = {}
"""


def _workspace_root() -> Path:
    if "BUILD_WORKSPACE_DIRECTORY" in os.environ:
        return Path(os.environ["BUILD_WORKSPACE_DIRECTORY"])

    return Path(__file__).parent.parent.parent


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)

    parser.add_argument(
        "--output",
        type=Path,
        default=_workspace_root() / "typst/private/versions.bzl",
        help="The path in which to save results.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging",
    )

    return parser.parse_args()


def _platform_from_asset_name(name: str) -> str | None:
    """Extract platform from asset name like typst-aarch64-apple-darwin.tar.xz."""
    if not name.startswith(TYPST_ASSET_PREFIX):
        return None
    for suffix in TYPST_ASSET_SUFFIXES:
        if name.endswith(suffix):
            return name[len(TYPST_ASSET_PREFIX) : -len(suffix)]
    return None


def integrity(hex_str: str) -> str:
    """Convert a sha256 hex value to a Bazel integrity value"""

    # Remove any whitespace and convert from hex to raw bytes
    try:
        raw_bytes = binascii.unhexlify(hex_str.strip())
    except binascii.Error as e:
        raise ValueError(f"Invalid hex input: {e}") from e

    # Convert to base64
    encoded = base64.b64encode(raw_bytes).decode("utf-8")
    return f"sha256-{encoded}"


def _integrity_from_digest(digest: str) -> str | None:
    """Parse GitHub digest 'sha256:hex' and return Bazel integrity 'sha256-base64'."""
    if not digest or ":" not in digest:
        return None
    _, hex_part = digest.split(":", 1)
    try:
        return integrity(hex_part)
    except (ValueError, binascii.Error):
        return None


def compute_integrity_from_url(url: str) -> str | None:
    """Download the resource at url, compute SHA256, and return Bazel integrity."""
    try:
        req = urllib.request.Request(url, headers=REQUEST_HEADERS)
        with urlopen(req) as resp:
            h = hashlib.sha256()
            while True:
                chunk = resp.read(DOWNLOAD_CHUNK_SIZE)
                if not chunk:
                    break
                h.update(chunk)
        return integrity(h.hexdigest())
    except Exception as e:
        logging.debug("Failed to download %s: %s", url, e)
        return None


def query_releases() -> dict[str, dict[str, dict[str, str]]]:
    """Fetch Typst releases and return version -> platform -> {urls, integrity}."""
    page = 1
    releases_data: dict[str, dict[str, dict[str, str]]] = {}
    version_regex = re.compile(TYPST_RELEASE_TAG_REGEX)
    while True:
        url = urlparse(TYPST_GITHUB_RELEASES_API_TEMPLATE.format(page=page))
        req = urllib.request.Request(url.geturl(), headers=REQUEST_HEADERS)
        logging.debug("Releases url: %s", url.geturl())

        try:
            with urlopen(req) as data:
                json_data = json.loads(data.read())
                if not json_data:
                    break
                for release in json_data:
                    regex = version_regex.match(release["tag_name"])
                    if not regex:
                        continue
                    version = regex.group(1)
                    logging.debug("Processing %s", version)

                    platforms: dict[str, dict[str, str]] = {}
                    for asset in release.get("assets", []):
                        name = asset.get("name", "")
                        platform = _platform_from_asset_name(name)
                        if platform is None:
                            continue
                        url_str = asset.get("browser_download_url")
                        if not url_str:
                            logging.debug(
                                "Skipping asset %s: no browser_download_url", name
                            )
                            continue
                        digest = asset.get("digest")
                        integrity_val = (
                            _integrity_from_digest(digest) if digest else None
                        )
                        if integrity_val is None:
                            logging.info("Computing integrity for %s %s", version, name)
                            integrity_val = compute_integrity_from_url(url_str)
                            time.sleep(0.5)  # Be nice to GitHub between downloads
                        if integrity_val is None:
                            logging.debug(
                                "Skipping asset %s: could not get integrity", name
                            )
                            continue
                        platforms[platform] = {
                            "urls": [url_str],
                            "integrity": integrity_val,
                        }
                        logging.debug("Matched asset for %s: %s", platform, name)

                    if platforms:
                        releases_data[version] = platforms
                        logging.debug(
                            "Version %s: %s platforms", version, len(platforms)
                        )
                    else:
                        logging.debug("No qualifying assets for version %s", version)

            page += 1
            time.sleep(0.5)
        except HTTPError as exc:
            if exc.code != 403:
                raise

            reset_time = exc.headers.get("x-ratelimit-reset")
            if not reset_time:
                raise

            sleep_duration = float(reset_time) - time.time()
            if sleep_duration < 0.0:
                continue

            logging.warning("%s", exc.msg)
            logging.debug("Waiting %ss for reset", sleep_duration)
            time.sleep(sleep_duration)

    return releases_data


def main() -> None:
    """The main entrypoint."""
    args = parse_args()

    if args.verbose:
        logging.basicConfig(level=logging.DEBUG)
    else:
        logging.basicConfig(level=logging.INFO)

    releases = query_releases()

    logging.debug("Writing to %s", args.output)
    args.output.write_text(BUILD_TEMPLATE.format(json.dumps(releases, indent=4)))
    logging.info("Done")


if __name__ == "__main__":
    main()
