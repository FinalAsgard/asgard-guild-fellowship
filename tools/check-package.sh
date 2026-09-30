#!/usr/bin/env bash
# Validates a built release zip: both production manifests and every file they
# load must be present, the manifests must agree on a real version, and nothing
# development-only may ship.
# Usage: tools/check-package.sh <package.zip>
# With EXPECTED_VERSION set (the release tag), the manifests must declare exactly it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/project.env
source "$repo_root/tools/project.env"
zip_path="${1:?usage: tools/check-package.sh <package.zip>}"
forbidden_patterns=(
    "^${ADDON}/spec/"
    "^${ADDON}/tools/"
    "^${ADDON}/docs/"
    "^${ADDON}/ai/"
    "^${ADDON}/\.github/"
    "^${ADDON}/\.pkgmeta$"
    "^${ADDON}/\.luacheckrc$"
    "^${ADDON}/\.busted$"
)

entries="$(unzip -Z1 "$zip_path")"
failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
has_entry() { printf '%s\n' "$entries" | grep -Fxq -- "$1"; }

versions=()
for manifest in "${MANIFESTS[@]}"; do
    path="${ADDON}/${manifest}"
    if ! has_entry "$path"; then
        fail "missing production manifest $path"
        continue
    fi
    contents="$(unzip -p "$zip_path" "$path" | tr -d '\r')"
    versions+=("$(printf '%s\n' "$contents" | sed -n 's/^## Version:[[:space:]]*//p')")
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        has_entry "${ADDON}/${file//\\//}" || fail "$manifest loads ${file}, which is not in the package"
    done < <(printf '%s\n' "$contents" | grep -v '^#' | grep -E '\.(lua|xml)$' || true)
done

if [ "${#versions[@]}" -eq 2 ] && [ "${versions[0]}" != "${versions[1]}" ]; then
    fail "production manifests disagree on version: ${versions[0]} vs ${versions[1]}"
fi
for version in "${versions[@]}"; do
    case "$version" in *@*@*) fail "packaged manifest still has an unreplaced placeholder: $version" ;; esac
    if [ -n "${EXPECTED_VERSION:-}" ] && [ "$version" != "$EXPECTED_VERSION" ]; then
        fail "packaged manifest declares version $version, not the release tag $EXPECTED_VERSION"
    fi
done

for pattern in "${forbidden_patterns[@]}"; do
    matches="$(printf '%s\n' "$entries" | grep -E -- "$pattern" || true)"
    [ -n "$matches" ] && fail "development-only files packaged: $(printf '%s' "$matches" | tr '\n' ' ')"
done

# Only the supported manifests may ship; any other would claim an unverified client.
extra="$(printf '%s\n' "$entries" | grep -E "^${ADDON}/[^/]+\.toc$" |
    grep -vFx -e "${ADDON}/${MANIFESTS[0]}" -e "${ADDON}/${MANIFESTS[1]}" || true)"
[ -n "$extra" ] && fail "unsupported manifests packaged: $(printf '%s' "$extra" | tr '\n' ' ')"

outside="$(printf '%s\n' "$entries" | grep -v "^${ADDON}/" || true)"
[ -n "$outside" ] && fail "files outside the ${ADDON}/ folder: $(printf '%s' "$outside" | tr '\n' ' ')"

if [ "$failures" -gt 0 ]; then
    echo "$failures package check(s) failed for $zip_path"
    exit 1
fi
echo "Package $zip_path passed: both production manifests, all loaded files, no development files."
