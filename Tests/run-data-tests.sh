#!/bin/bash
#
# Runs the data-protection scenarios against the real app sources.
#
# These cover the ways workout history can be lost: upgrading from the old
# archive format, corrupted files, missing files, and unusable backups. They
# compile DataObject.swift and DataMigrationManager.swift directly (both are
# Foundation-only) and run them against a throwaway Documents directory, so no
# simulator or test target is needed.
#
# Usage:  ./Tests/run-data-tests.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Top-level code is only allowed in a file named main.swift.
cp "$ROOT/Tests/DataProtectionScenarios.swift" "$WORK/main.swift"

swiftc -o "$WORK/runner" \
    "$WORK/main.swift" \
    "$ROOT/buttons/DataObject.swift" \
    "$ROOT/buttons/DataMigrationManager.swift"

# CFFIXED_USER_HOME redirects FileManager's .documentDirectory, so the tests
# never touch the real ~/Documents.
mkdir -p "$WORK/home/Documents"
CFFIXED_USER_HOME="$WORK/home" "$WORK/runner"
