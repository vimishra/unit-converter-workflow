#!/bin/bash

# Build converter.swift into the universal binary shipped with the Workflow

set -euo pipefail

readonly deployment_target='13.0'  # Swift Regex literals require macOS 13

cd "$(dirname "${0}")"
readonly tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

for arch in arm64 x86_64; do
  swiftc -O -target "${arch}-apple-macos${deployment_target}" -o "${tmp_dir}/converter-${arch}" converter.swift
done

lipo -create -output ../Workflow/converter "${tmp_dir}/converter-arm64" "${tmp_dir}/converter-x86_64"

# lipo leaves the merged binary unsigned, and arm64 refuses to run unsigned code.
# Ad-hoc is the best we can do without a Developer ID; see the README on quarantine.
codesign --force --sign - --identifier converter ../Workflow/converter
