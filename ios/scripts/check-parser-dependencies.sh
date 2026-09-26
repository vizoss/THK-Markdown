#!/bin/bash
# Read otool -L output. Headers contain the input path (including THK-Markdown)
# and are not dependencies. Match parser library names, not arbitrary path text.
set -euo pipefail
awk '
  /^[[:space:]]/ && /\/(lib)?(Markdown|Maaku|cmark[^\/]*)(\.framework\/|\.dylib([[:space:]]|$))/ {
    print "Unexpected external parser dependency: " $0
    found = 1
  }
  END { exit found ? 1 : 0 }
'
