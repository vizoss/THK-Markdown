#!/bin/bash
# Validate textual interfaces explicitly: matching compiler .swiftmodule caches
# can otherwise hide broken interfaces until a consumer upgrades Xcode.
set -euo pipefail
framework="${1:?Usage: check-binary-consumer.sh framework sdk target [target...]}"
sdk="${2:?Missing SDK}"
shift 2
[[ $# -gt 0 && -d "$framework/Modules/THKMDView.swiftmodule" ]] || exit 1
script_dir="$(cd "$(dirname "$0")" && pwd)"
sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
framework_parent="$(cd "$(dirname "$framework")" && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/thk-binary-consumer.XXXXXX")"
for target in "$@"; do
  arch="${target%%-*}"
  interfaces=("$framework/Modules/THKMDView.swiftmodule/$arch"-*.swiftinterface)
  [[ -f "${interfaces[0]}" ]] || { echo "No interfaces for $target" >&2; exit 1; }
  for interface in "${interfaces[@]}"; do
    xcrun swift-frontend -typecheck-module-from-interface "$interface" \
      -module-name THKMDView -target "$target" -sdk "$sdk_path" \
      -F "$framework_parent" -module-cache-path "$check_dir/cache"
  done
  xcrun swiftc "$script_dir/fixtures/BinaryConsumer.swift" \
    -emit-library -module-name THKBinaryConsumer -target "$target" \
    -sdk "$sdk_path" -F "$framework_parent" -framework THKMDView \
    -module-cache-path "$check_dir/cache" \
    -o "$check_dir/THKBinaryConsumer-$arch.dylib"
done
echo "Binary interfaces and consumer linking passed: $framework ($sdk)"
