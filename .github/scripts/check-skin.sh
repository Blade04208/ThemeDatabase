#!/usr/bin/env bash
set -uo pipefail

entry="$1"
strict="${2:-strict}"
owner="${entry%%/*}"
repo="${entry##*/}"

if ! skin=$(timeout 30 gh api "repos/$entry/contents/skin.json" -H 'Accept: application/vnd.github.raw' 2>/dev/null); then
    echo "::error::$entry has no skin.json at its root"
    exit 1
fi

if ! jq -e 'type == "object"' <<<"$skin" >/dev/null 2>&1; then
    echo "::error::$entry has a skin.json that is not valid JSON"
    exit 1
fi

[ "$strict" = "strict" ] || exit 0

failed=0

skin_owner=$(jq -r '.github.owner // empty' <<<"$skin")
skin_repo=$(jq -r '.github.repo_name // empty' <<<"$skin")

if [ "${skin_owner,,}" != "${owner,,}" ]; then
    echo "::error::$entry skin.json github.owner is \"$skin_owner\" but should be \"$owner\""
    failed=1
fi

if [ "${skin_repo,,}" != "${repo,,}" ]; then
    echo "::error::$entry skin.json github.repo_name is \"$skin_repo\" but should be \"$repo\""
    failed=1
fi

for field in header_image splash_image; do
    url=$(jq -r --arg f "$field" '.[$f] // empty' <<<"$skin")

    if [ -z "$url" ]; then
        echo "::error::$entry skin.json is missing $field"
        failed=1
        continue
    fi

    case "$url" in
        https://*) ;;
        *)
            echo "::error::$entry $field must be an https URL"
            failed=1
            continue
            ;;
    esac

    result=$(curl --silent --location --max-time 20 --range 0-1023 --output /dev/null --write-out '%{http_code} %{content_type}' "$url" 2>/dev/null || echo "000 none")
    code="${result%% *}"
    type="${result#* }"

    if [ "$code" != "200" ] && [ "$code" != "206" ]; then
        echo "::error::$entry $field returned HTTP $code ($url)"
        failed=1
    elif [[ "$type" != image/* ]] && ! { [[ "$type" == application/octet-stream ]] && [[ "${url%%[?#]*}" =~ \.(png|jpe?g|gif|webp|avif|svg)$ ]]; }; then
        echo "::error::$entry $field is not an image, got \"$type\" ($url)"
        failed=1
    fi
done

exit $failed
