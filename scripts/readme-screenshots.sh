#!/usr/bin/env bash
# Turns the `screenshots` artifact of a green CI run into the README images in
# docs/screenshots: 600 px wide, rounded like the iPhone's display, no metadata.
#
#   gh run download <run id> -n screenshots -D /tmp/shots
#   nix shell nixpkgs#imagemagick nixpkgs#oxipng nixpkgs#jq -c scripts/readme-screenshots.sh /tmp/shots
set -euo pipefail
cd "$(dirname "$0")/.."

artifact=${1:?usage: $0 <screenshots artifact directory>}

# README name <- UI tour screenshot name (see OpenGrindUITests/DemoTourTests.swift).
shots=(
    welcome:01-welcome
    nearby:03-browse
    explore:12-explore
    profile:05-profile
    chat:07-chat
    messages:08-messages
    interest:09-interest
    edit-profile:18-edit-profile
    photos:14-photos
)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for shot in "${shots[@]}"; do
    name=${shot%%:*} tour=${shot#*:}
    file=$(jq -r --arg tour "$tour" \
        '[.[].attachments[] | select(.suggestedHumanReadableName | startswith($tour + "_"))][0].exportedFileName // empty' \
        "$artifact/manifest.json")
    if [[ -z $file ]]; then
        echo "no $tour screenshot in $artifact" >&2
        exit 1
    fi
    magick "$artifact/$file" -resize 600x -strip "$work/plain.png"
    read -r width height < <(magick identify -format '%w %h\n' "$work/plain.png")
    radius=84 # The iPhone 17 Pro's corner radius at this width.
    magick "$work/plain.png" \
        \( -size "${width}x${height}" xc:none -fill white \
        -draw "roundrectangle 0,0,$((width - 1)),$((height - 1)),$radius,$radius" \) \
        -alpha set -compose DstIn -composite \
        \( -size "${width}x${height}" xc:none -fill none -stroke 'rgba(128,128,128,0.45)' -strokewidth 2 \
        -draw "roundrectangle 1,1,$((width - 2)),$((height - 2)),$((radius - 1)),$((radius - 1))" \) \
        -compose Over -composite "docs/screenshots/$name.png"
    oxipng -q -o 4 --strip all "docs/screenshots/$name.png"
    echo "docs/screenshots/$name.png <- $tour"
done
