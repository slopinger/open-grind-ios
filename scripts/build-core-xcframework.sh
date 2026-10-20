#!/usr/bin/env bash
# Builds the Rust bridge (core/) for iPhone, the iOS Simulator and macOS, and packs
# it as OpenGrindKit/Frameworks/opengrind_coreFFI.xcframework, which Package.swift
# uses on Apple platforms. Needs Xcode, plus Rust with the three targets, cmake and perl:
# run it in the flake's shell (`nix develop -c scripts/build-core-xcframework.sh`), or
# install them yourself (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin`).
set -euo pipefail
cd "$(dirname "$0")/.."

targets=(aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin)
export IPHONEOS_DEPLOYMENT_TARGET=18.0
export MACOSX_DEPLOYMENT_TARGET=15.0

for target in "${targets[@]}"; do
    cargo rustc --manifest-path core/Cargo.toml --release --lib --crate-type staticlib --target "$target"
done

headers=$(mktemp -d)
trap 'rm -rf "$headers"' EXIT
cp OpenGrindKit/Sources/opengrind_coreFFI/include/opengrind_coreFFI.h "$headers/"
cat >"$headers/module.modulemap" <<'MODULEMAP'
module opengrind_coreFFI {
    header "opengrind_coreFFI.h"
    export *
}
MODULEMAP

output=OpenGrindKit/Frameworks/opengrind_coreFFI.xcframework
rm -rf "$output"
arguments=()
for target in "${targets[@]}"; do
    arguments+=(-library "core/target/$target/release/libopengrind_core.a" -headers "$headers")
done
xcodebuild -create-xcframework "${arguments[@]}" -output "$output"
echo "Built $output"
