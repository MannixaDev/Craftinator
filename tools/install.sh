#!/usr/bin/env bash
# Copy the addon into a WoW AddOns folder for testing. Run from the repo root:
#   tools/install.sh "/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"
set -euo pipefail
target="${1:?usage: tools/install.sh <path to Interface/AddOns>}/Craftinator"
rm -rf "$target"
mkdir -p "$target"
cp -r Craftinator.toc ./*.lua Data UI "$target/"
echo "installed to $target"
