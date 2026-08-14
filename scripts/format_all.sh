#!/bin/bash
PACKAGES=$(find . -name node_modules -prune -or -name package.json -exec dirname {} \;)
for package in $PACKAGES; do
  (cd "$package" && npm run format --silent --if-present 2>&1 | grep -v '(unchanged)' | sed "s#^#[formatted $package] #")
done
