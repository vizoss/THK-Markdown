#!/bin/bash
# Only exact x.y.z tags may publish; manual dispatch must also select a tag.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${GITHUB_REF_TYPE:-}" != tag || ! "${GITHUB_REF_NAME:-}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo 'Release builds require an x.y.z tag, for example 1.0.0 (no v prefix).' >&2
  exit 1
fi
android_version="$(sed -n 's/^VERSION_NAME=//p' "$project_root/android/gradle.properties")"
ios_version="$(sed -n "s/^  s.version = '\([^']*\)'/\1/p" "$project_root/THKMDView.podspec")"
if [[ "$GITHUB_REF_NAME" != "$android_version" || "$GITHUB_REF_NAME" != "$ios_version" ]]; then
  echo "Tag $GITHUB_REF_NAME does not match Android $android_version and iOS $ios_version" >&2
  exit 1
fi
echo "$GITHUB_REF_NAME"
