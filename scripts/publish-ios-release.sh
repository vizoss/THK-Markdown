#!/bin/bash
# Publish only the verified artifact from an immutable tag build, never a branch candidate.
set -euo pipefail
[[ "$BUILD_RUN_ID" =~ ^[0-9]+$ ]] || { echo 'Invalid build run ID'; exit 1; }
run_json=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$BUILD_RUN_ID")
version=$(jq -r '.head_branch' <<< "$run_json")
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 1
jq -e --arg repo "$GITHUB_REPOSITORY" '
  .conclusion == "success" and .event == "push" and
  .path == ".github/workflows/ios-podspec-lint.yml" and
  .repository.full_name == $repo and .head_repository.full_name == $repo
' <<< "$run_json" >/dev/null
build_sha=$(jq -r '.head_sha' <<< "$run_json")
tag_sha=$(gh api "repos/$GITHUB_REPOSITORY/commits/$version" --jq '.sha')
[[ "$build_sha" == "$tag_sha" ]] || { echo 'Tag differs from verified build'; exit 1; }

download_dir=$(mktemp -d "$RUNNER_TEMP/thk-ios-release.XXXXXX")
gh run download "$BUILD_RUN_ID" --repo "$GITHUB_REPOSITORY" \
  --name "THKMDView-$version-binary" --dir "$download_dir"
mapfile -t archives < <(find "$download_dir" -name "THKMDView-$version.zip" -type f)
mapfile -t checksums < <(find "$download_dir" -name SHA256SUMS -type f)
mapfile -t podspecs < <(find "$download_dir" -name THKMDView.podspec -type f)
[[ ${#archives[@]} == 1 && ${#checksums[@]} == 1 && ${#podspecs[@]} == 1 ]] || exit 1
expected=$(awk 'NR == 1 {print $1}' "${checksums[0]}")
actual=$(sha256sum "${archives[0]}" | awk '{print $1}')
[[ "$expected" =~ ^[0-9a-f]{64}$ && "$actual" == "$expected" ]] || { echo 'Artifact checksum mismatch'; exit 1; }
grep -F "s.version = '$version'" "${podspecs[0]}"
# Normalize the checksum manifest so consumers can use sha256sum -c after download.
printf '%s  THKMDView-%s.zip\n' "$actual" "$version" > "$download_dir/SHA256SUMS"

# Never replace an existing release or silently overwrite a published binary.
if gh release view "$version" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  echo "Release $version already exists; refusing to overwrite it"
  exit 1
fi
gh release create "$version" --repo "$GITHUB_REPOSITORY" --verify-tag --draft \
  --title "THKMDView $version" \
  --notes "Precompiled iOS XCFramework. Device/simulator archives and CocoaPods integration lint passed in build $BUILD_RUN_ID. Includes parser and offline rendering resources; no example app. Android is available from the public maven-repo branch." \
  "${archives[0]}" "$download_dir/SHA256SUMS" "${podspecs[0]}"
gh release edit "$version" --repo "$GITHUB_REPOSITORY" --draft=false
echo "Published https://github.com/$GITHUB_REPOSITORY/releases/tag/$version" >> "$GITHUB_STEP_SUMMARY"
