#!/bin/bash
# format every package; when running as a git pre-commit hook, re-stage the
# files that were already fully staged so the formatting lands in the commit;
# a partially staged file is being committed surgically, so its formatting is
# left out of the commit and reported

# files staged for commit (added, copied, modified, renamed) before formatting
staged=()
partial=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r -d '' path; do
    staged+=("$path")
  done < <(git diff --cached --name-only -z --diff-filter=ACMR)
  # a file with both staged and unstaged changes is partially staged
  while IFS= read -r -d '' path; do
    partial+=("$path")
  done < <(git diff --name-only -z)
fi

PACKAGES=$(find . -name node_modules -prune -or -name package.json -exec dirname {} \;)
for package in $PACKAGES; do
  (cd "$package" && npm run format --silent --if-present 2>&1 | grep -v '(unchanged)' | sed "s#^#[formatted $package] #")
done

for path in "${staged[@]}"; do
  skip=0
  for other in "${partial[@]}"; do
    if [ "$path" = "$other" ]; then
      skip=1
      break
    fi
  done
  if [ "$skip" = 1 ]; then
    echo "[format hook] $path: partially staged, committed content not formatted"
  else
    git add -- "$path"
  fi
done
