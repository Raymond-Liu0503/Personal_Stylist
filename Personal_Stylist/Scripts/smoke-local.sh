#!/bin/zsh
set -eu
cd "${0:A:h}/.."
task_build_dir=$(mktemp -d /tmp/stylist-smoke.XXXXXX)
trap 'rm -rf "$task_build_dir"' EXIT
swiftc -DDEBUG -swift-version 5 -parse-as-library -module-cache-path "$task_build_dir/modules" Core/*.swift Scripts/LocalSmoke.swift -o "$task_build_dir/smoke"
"$task_build_dir/smoke"
