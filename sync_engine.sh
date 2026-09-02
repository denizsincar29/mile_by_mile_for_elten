#!/usr/bin/env bash
# Copies the game engine (lib/mile_by_mile) into src/lib/mile_by_mile.
# An Elten app is a self-contained folder (packaged as a whole), so we
# keep a separate copy of the engine inside it. Run this after any changes
# to lib/mile_by_mile, before committing.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf src/lib/mile_by_mile
cp -r lib/mile_by_mile src/lib/mile_by_mile
echo "src/lib/mile_by_mile synced with lib/mile_by_mile"
