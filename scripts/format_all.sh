#!/bin/bash
# format every source the build knows how to format and name the files that
# were rewritten; when running as a git pre-commit hook, re-stage the files
# that were already fully staged so the formatting lands in the commit; a
# partially staged file is being committed surgically, so its formatting is
# left out of the commit and reported
#
# runs from the repository root, where git runs its hooks

# the files with an unstaged change, which git names as they are, so that a
# file reformatted below shows up as a new entry; empty outside a work tree
unstaged_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git diff --name-only -z
  fi
}

# files staged for commit (added, copied, modified, renamed) before formatting
staged=()
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r -d '' path; do
    staged+=("$path")
  done < <(git diff --cached --name-only -z --diff-filter=ACMR)
fi
# a staged file with an unstaged change as well is partially staged
partial=()
while IFS= read -r -d '' path; do
  partial+=("$path")
done < <(unstaged_files)

# the root `make format` picks a configured build tree, configures it first
# when it is missing or stale, and builds its format target: every formatter
# the build registered, each over exactly the files its provider declared
# (see derammo_format.cmake); its output is shown only when it fails, and
# then the commit proceeds, since the lint tests are the gate, not this hook
make_log=$(mktemp)
if ! make format >"$make_log" 2>&1; then
  sed "s#^#[format] #" "$make_log"
  echo "[format hook] formatting skipped: make format failed, see above"
fi
rm -f "$make_log"

# a file with an unstaged change now that had none before was rewritten by a
# formatter; reported whether staged or not, since an unstaged file that
# needed formatting was edited with the wrong settings somewhere
while IFS= read -r -d '' path; do
  rewritten=1
  for other in "${partial[@]}"; do
    if [ "$path" = "$other" ]; then
      rewritten=0
      break
    fi
  done
  if [ "$rewritten" = 1 ]; then
    echo "[format hook] reformatted $path"
  fi
done < <(unstaged_files)

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
