#!/bin/bash
# Build only when explicitly invoked; never launches an app or publishes artifacts.
set -euo pipefail
trap 'echo "Binary packaging failed at line $LINENO: $BASH_COMMAND" >&2' ERR
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
command -v xcodegen >/dev/null || { echo "Install XcodeGen first."; exit 1; }
command -v pod >/dev/null || { echo "Install CocoaPods first (for binary integration lint)."; exit 1; }
version="$(ruby -e 'puts File.read(ARGV[0]).match(/s\.version = .([0-9]+\.[0-9]+\.[0-9]+)./)[1]' "$project_root/THKMDView.podspec")"
build_dir="$(mktemp -d "$project_root/ios/Binary/build-XXXXXX")"
export THK_BINARY_BUILD_DIR="$build_dir"
# Validate parser pin before any network resolution.
ruby -rjson -ryaml -e '
  lock = JSON.parse(File.read(ARGV[0]))
  spec = YAML.load_file(ARGV[1])
  pin = lock.fetch("pins").find { |p| p["identity"] == "swift-markdown" }.fetch("state").fetch("revision")
  abort "Binary parser revision differs from SPM lock" unless pin == spec["packages"]["swift-markdown"]["revision"]
' "$project_root/ios/Package.resolved" "$project_root/ios/Binary/project.yml"
xcodegen generate --spec "$project_root/ios/Binary/project.yml"
project="$project_root/ios/Binary/THKMDViewBinary.xcodeproj"
mkdir -p "$project/project.xcworkspace/xcshareddata/swiftpm"
ruby -rjson -e '
  lock = JSON.parse(File.read(ARGV[0]))
  lock.fetch("pins").find { |p| p["identity"] == "swift-markdown" }.fetch("state").delete("branch")
  File.write(ARGV[1], JSON.pretty_generate(lock))
' "$project_root/ios/Package.resolved" "$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
common=(-project "$project" -scheme THKMDView -configuration Release
  -clonedSourcePackagesDirPath "$build_dir/packages" -derivedDataPath "$build_dir/DerivedData"
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO)
xcodebuild archive "${common[@]}" -destination 'generic/platform=iOS' -archivePath "$build_dir/device" ARCHS=arm64
xcodebuild archive "${common[@]}" -destination 'generic/platform=iOS Simulator' -archivePath "$build_dir/simulator" 'ARCHS=arm64 x86_64'
device="$build_dir/device.xcarchive/Products/Library/Frameworks/THKMDView.framework"
simulator="$build_dir/simulator.xcarchive/Products/Library/Frameworks/THKMDView.framework"
# Fail on accidental runtime dependencies or parser imports exposed to consumers.
for framework in "$device" "$simulator"; do
  test -f "$framework/mermaid_template.html"
  test -f "$framework/mermaid.min.js"
  test -f "$framework/math_template.html"
  test -f "$framework/mathjax-3.2.2.js"
  test -f "$framework/mathjax-LICENSE.txt"
  xcrun otool -L "$framework/THKMDView" | bash "$project_root/ios/scripts/check-parser-dependencies.sh"
  if grep -RE 'import (Markdown|cmark|cmark_gfm|Maaku)' "$framework/Modules/THKMDView.swiftmodule/"*.swiftinterface; then
    echo "Parser leaked into public interface"; exit 1
  fi
done
xcrun lipo "$device/THKMDView" -verify_arch arm64
xcrun lipo "$simulator/THKMDView" -verify_arch arm64 x86_64
release="$build_dir/release"
mkdir -p "$release/THIRD_PARTY_LICENSES"
xcodebuild -create-xcframework -framework "$device" -framework "$simulator" -output "$release/THKMDView.xcframework"
cp "$project_root/LICENSE" "$release/LICENSE"
cp "$build_dir/packages/checkouts/swift-markdown/LICENSE.txt" "$release/THIRD_PARTY_LICENSES/swift-markdown-LICENSE.txt"
cp "$build_dir/packages/checkouts/swift-markdown/NOTICE.txt" "$release/THIRD_PARTY_LICENSES/swift-markdown-NOTICE.txt"
cp "$build_dir/packages/checkouts/swift-cmark/COPYING" "$release/THIRD_PARTY_LICENSES/swift-cmark-COPYING.txt"
# Mermaid's embedded license banner is retained in the shipped JS resource.
cp "$project_root/THKMDView.podspec" "$release/THKMDView.podspec"
# Local lint proves a CocoaPods consumer can compile without Markdown/Maaku installed.
(cd "$release" && pod lib lint THKMDView.podspec --allow-warnings --skip-tests)
(cd "$release" && /usr/bin/zip -qr "$build_dir/THKMDView-$version.zip" THKMDView.xcframework LICENSE THIRD_PARTY_LICENSES)
shasum -a 256 "$build_dir/THKMDView-$version.zip" > "$build_dir/SHA256SUMS"
echo "Local binary artifact: $build_dir/THKMDView-$version.zip"
echo "Not published. Upload the zip to release $version before remote pod installation."
