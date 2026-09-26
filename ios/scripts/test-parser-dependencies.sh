#!/bin/bash
set -euo pipefail
checker="$(cd "$(dirname "$0")" && pwd)/check-parser-dependencies.sh"

# Regression: the repository path is a header, not a linked parser dependency.
bash "$checker" <<'INPUT'
/Users/runner/work/THK-Markdown/THK-Markdown/THKMDView.framework/THKMDView:
    @rpath/THKMDView.framework/THKMDView (compatibility version 1.0.0)
    /System/Library/Frameworks/UIKit.framework/UIKit (compatibility version 1.0.0)
    /usr/lib/libswiftCore.dylib (compatibility version 1.0.0)
INPUT

for dependency in '@rpath/Markdown.framework/Markdown' '@rpath/Maaku.framework/Maaku' '@rpath/libcmark-gfm.dylib' '@rpath/libcmark.dylib'; do
  if printf '    %s (compatibility version 1.0.0)\n' "$dependency" | bash "$checker"; then
    echo "FAIL: parser dependency was accepted: $dependency" >&2
    exit 1
  fi
done
echo 'Parser dependency checks passed.'
