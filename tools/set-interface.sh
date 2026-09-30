#!/usr/bin/env bash
# Sets the game interface version(s) one client supports, in its production
# manifest and the README client table.
#
# Usage: tools/set-interface.sh <forever|retail> <interface> [interface...]
#   tools/set-interface.sh retail 120200
#   tools/set-interface.sh forever 16001 16002
#
# Read a client's interface in game with: /dump (select(4, GetBuildInfo()))
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/project.env
source "$repo_root/tools/project.env"

usage() { echo "Usage: tools/set-interface.sh <forever|retail> <interface> [interface...]" >&2; exit 1; }
[ "$#" -ge 2 ] || usage
client="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
shift

case "$client" in
    forever) manifest="${ADDON}_Camelot.toc"; readme_label="World of Warcraft: Forever" ;;
    retail) manifest="${ADDON}_Mainline.toc"; readme_label="World of Warcraft Retail" ;;
    *) usage ;;
esac

for interface in "$@"; do
    if [[ ! "$interface" =~ ^[1-9][0-9]{4,5}$ ]]; then
        echo "Interface versions are 5 or 6 digit numbers, such as 16001 or 120100; got '$interface'." >&2
        exit 1
    fi
done

toc_value="$(printf '%s, ' "$@")"; toc_value="${toc_value%, }"
readme_value="$(printf '`%s`, ' "$@")"; readme_value="${readme_value%, }"
export toc_value readme_value readme_label

perl -pi -e 's/^## Interface:.*$/## Interface: $ENV{toc_value}/' "$repo_root/$manifest"
# Replace only the last column of this client's README table row.
perl -pi -e 's/^(\| \Q$ENV{readme_label}\E \|.*\| )[^|]*( \|)$/$1$ENV{readme_value}$2/' "$repo_root/README.md"

status=0
grep -qxF "## Interface: $toc_value" "$repo_root/$manifest" || { echo "Not updated: $manifest" >&2; status=1; }
grep -F "| $readme_label |" "$repo_root/README.md" | grep -qF "$readme_value |" \
    || { echo "Not updated: README.md" >&2; status=1; }
[ "$status" -eq 0 ] && echo "Set $client to interface $toc_value in $manifest and README.md."
exit "$status"
