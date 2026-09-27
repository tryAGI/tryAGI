#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../audit-generated-sdks.sh
source "$script_dir/../audit-generated-sdks.sh"

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
ROOT_DIR="$test_root"
mkdir -p "$test_root/LocalTool/.config" "$test_root/LocalTool/src/libs/LocalTool"
cat > "$test_root/LocalTool/.config/dotnet-tools.json" <<'JSON'
{"version":1,"isRoot":true,"tools":{"autosdk.cli":{"version":"1.0.0","commands":["autosdk"]}}}
JSON
cat > "$test_root/LocalTool/src/libs/LocalTool/generate.sh" <<'SH'
dotnet tool restore
dotnet tool run autosdk generate openapi.yaml
SH

[[ "$(repo_autosdk_bootstrap_info LocalTool)" == $'ok\t' ]]

sed -i.bak '/dotnet tool restore/d' "$test_root/LocalTool/src/libs/LocalTool/generate.sh"
[[ "$(repo_autosdk_bootstrap_info LocalTool)" == $'missing-bootstrap\tsrc/libs/LocalTool/generate.sh' ]]

echo "local AutoSDK tool bootstrap tests passed"
