#!/usr/bin/env bash
# Builds the multi-client release zip locally with the BigWigs packager, never
# uploading, then validates its contents.
# Usage: tools/build-package.sh [release-dir]   (default: .release)
# The packager needs bash 4.3+. macOS ships 3.2, so point PACKAGER_BASH at a
# newer bash (for example /opt/homebrew/bin/bash from `brew install bash`).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_dir="${1:-$repo_root/.release}"
packager_bash="${PACKAGER_BASH:-bash}"
# shellcheck source=tools/project.env
source "$repo_root/tools/project.env"

if ! "$packager_bash" -c '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) ))'; then
    echo "The packager needs bash 4.3 or newer; '$packager_bash' is older. Set PACKAGER_BASH to a newer bash." >&2
    exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
# Build into an empty staging directory so an older zip is never the one validated.
staging_dir="$work_dir/release"

curl -fsSL "https://raw.githubusercontent.com/BigWigsMods/packager/${PACKAGER_COMMIT}/release.sh" \
    -o "$work_dir/release.sh"
# -d: never upload anywhere. The result is only a local zip.
"$packager_bash" "$work_dir/release.sh" -d -t "$repo_root" -r "$staging_dir" | tee "$work_dir/packager.log"

# A manifest suffix the packager doesn't recognize silently drops that client.
if ! grep -q '^Build type: multi-version' "$work_dir/packager.log"; then
    echo "The packager did not tag this build for both Forever and Retail. Check the manifest suffixes." >&2
    exit 1
fi

staged_zips=("$staging_dir"/"$ADDON"-*.zip)
if [ "${#staged_zips[@]}" -ne 1 ] || [ ! -f "${staged_zips[0]}" ]; then
    echo "Expected exactly one package in $staging_dir." >&2
    exit 1
fi
"$repo_root/tools/check-package.sh" "${staged_zips[0]}"

mkdir -p "$release_dir"
zip_path="$release_dir/$(basename "${staged_zips[0]}")"
mv -f "${staged_zips[0]}" "$zip_path"
echo "Built $zip_path"
