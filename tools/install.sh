#!/usr/bin/env bash
# Copy the addon into a WoW AddOns folder for testing, as a separate addon called "Craftinator-Dev",
# so the CurseForge release can stay installed in "Craftinator" next to it. Enable one of the two
# in the game's AddOns list. Run from the repo root:
#   tools/install.sh "/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"
# The dev copy keeps its own saved data: SavedVariables/Craftinator-Dev.lua.
set -euo pipefail
name="Craftinator-Dev"
target="${1:?usage: tools/install.sh <path to Interface/AddOns>}/$name"
rm -rf "$target"
mkdir -p "$target"
cp -r ./*.lua Data UI "$target/"
sed -e 's/^## Title: Craftinator$/## Title: Craftinator |cffff8000(dev)|r/' Craftinator.toc > "$target/$name.toc"
echo "installed to $target"
