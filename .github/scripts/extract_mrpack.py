#!/usr/bin/env python3
"""
.github/scripts/extract_mrpack.py
──────────────────────────────────────────────────────────────────────────────
Extracts an mrpack (Modrinth modpack archive) into a run/ directory suitable
for mc-runtime-test.

• Copies all overrides into run/
• Downloads every file declared in modrinth.index.json into run/<path>
• Skips files whose SHA-1 already matches (idempotent re-runs)
• Retries failed downloads up to 3 times with exponential backoff

Usage:
    python3 .github/scripts/extract_mrpack.py [--mrpack-dir build/modrinth]
"""

import zipfile
import json
import urllib.request
import os
import sys
import hashlib
import time
import glob
import argparse
import concurrent.futures


def find_mrpack(search_dir: str) -> str:
    """Locate the first .mrpack file under search_dir."""
    matches = glob.glob(os.path.join(search_dir, "*.mrpack"))
    if not matches:
        print(f"  [FAIL]  No .mrpack found under {search_dir}", file=sys.stderr)
        sys.exit(1)
    return matches[0]


def extract_overrides(z: zipfile.ZipFile, dest: str) -> int:
    """Copy override files from the archive into dest/."""
    count = 0
    for name in z.namelist():
        if name.startswith("overrides/") and not name.endswith("/"):
            rel = name[len("overrides/"):]
            out = os.path.join(dest, rel)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "wb") as f:
                f.write(z.read(name))
            count += 1
    return count


def download_file(f: dict, dest_root: str) -> tuple[str, str]:
    """Download a single file entry from modrinth.index.json into dest_root/."""
    url = f["downloads"][0]
    path = f["path"]
    dest = os.path.join(dest_root, path)
    os.makedirs(os.path.dirname(dest), exist_ok=True)

    # Skip if the file is already present and hash matches
    if os.path.exists(dest) and "hashes" in f:
        sha1 = f["hashes"].get("sha1", "")
        if sha1:
            with open(dest, "rb") as fp:
                if hashlib.sha1(fp.read()).hexdigest() == sha1:
                    return path, "skip"

    for attempt in range(3):
        try:
            urllib.request.urlretrieve(url, dest)
            return path, "ok"
        except Exception as e:
            if attempt == 2:
                return path, f"FAIL: {e}"
            time.sleep(2 ** attempt)

    return path, "FAIL: exhausted retries"


def main():
    parser = argparse.ArgumentParser(description="Extract mrpack into run/")
    parser.add_argument(
        "--mrpack-dir",
        default="build/modrinth",
        help="Directory containing the .mrpack file (default: build/modrinth)",
    )
    parser.add_argument(
        "--dest",
        default="run",
        help="Destination game directory (default: run)",
    )
    args = parser.parse_args()

    mrpack = find_mrpack(args.mrpack_dir)
    print(f"  [INFO]  Extracting: {mrpack}")

    with zipfile.ZipFile(mrpack, "r") as z:
        index = json.loads(z.read("modrinth.index.json"))

        override_count = extract_overrides(z, args.dest)
        if override_count:
            print(f"  [OK]    {override_count} override file(s) extracted")

    files = index.get("files", [])
    print(f"  [INFO]  Downloading {len(files)} mod/resource file(s)...")

    failed = []
    ok_count = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        futures = {pool.submit(download_file, f, args.dest): f for f in files}
        for future in concurrent.futures.as_completed(futures):
            path, status = future.result()
            if status == "ok":
                ok_count += 1
            elif status == "skip":
                pass
            else:
                failed.append(f"{path}: {status}")

    if failed:
        for f in failed:
            print(f"  [FAIL]  {f}", file=sys.stderr)
        sys.exit(1)

    print(f"  [OK]    {ok_count} file(s) downloaded into {args.dest}/")


if __name__ == "__main__":
    main()
