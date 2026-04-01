#!/usr/bin/env bash
set -euo pipefail

# create-sdk.sh — Automates creation of new AutoSDK-based .NET SDKs for tryAGI
#
# Usage:
#   ./create-sdk.sh <SdkName> <ClientClassName> <spec-url> [description] [tags]
#
# Examples:
#   ./create-sdk.sh Cartesia CartesiaClient "https://api.example.com/openapi.json" \
#     "Low-latency TTS, STT, voice cloning" \
#     "cartesia;tts;stt;voice"
#
# What it does:
#   1. Scaffolds project with autosdk init
#   2. Runs generate.sh to produce Generated/ code
#   3. Builds the solution
#   4. Inits git, commits, creates GitHub repo, pushes
#   5. Sets repo metadata (description, homepage, topics)
#   6. Syncs docs from example tests

readonly SDK_NAME="${1:?Usage: $0 <SdkName> <ClientClassName> <spec-url> [description] [tags]}"
readonly CLIENT_CLASS="${2:?Usage: $0 <SdkName> <ClientClassName> <spec-url> [description] [tags]}"
readonly SPEC_URL="${3:?Usage: $0 <SdkName> <ClientClassName> <spec-url> [description] [tags]}"
readonly DESCRIPTION="${4:-Generated C# SDK for ${SDK_NAME}.}"
readonly TAGS="${5:-api;sdk;dotnet;openapi;generated}"
readonly ORG="tryAGI"
readonly BASE_DIR="/Users/havendv/GitHub/tryAGI"

echo "=== Creating ${SDK_NAME} SDK ==="

# Step 1: Scaffold
echo "[1/7] Scaffolding with autosdk init..."
cd "$BASE_DIR"
autosdk init "$SDK_NAME" "$CLIENT_CLASS" "$SPEC_URL" "$ORG" --add-mkdocs --add-tests

cd "${BASE_DIR}/${SDK_NAME}"

# Step 2: Update csproj metadata
echo "[2/7] Updating csproj metadata..."
CSPROJ="src/libs/${SDK_NAME}/${SDK_NAME}.csproj"
if [ -f "$CSPROJ" ]; then
    # Use sed to update description and tags
    sed "s|<Description>.*</Description>|<Description>${DESCRIPTION}</Description>|" "$CSPROJ" > "$CSPROJ.tmp" && mv "$CSPROJ.tmp" "$CSPROJ"
    sed "s|<PackageTags>.*</PackageTags>|<PackageTags>${TAGS}</PackageTags>|" "$CSPROJ" > "$CSPROJ.tmp" && mv "$CSPROJ.tmp" "$CSPROJ"
fi

# Step 3: Generate
echo "[3/7] Generating SDK..."
chmod +x "src/libs/${SDK_NAME}/generate.sh"
cd "src/libs/${SDK_NAME}"
./generate.sh
cd "${BASE_DIR}/${SDK_NAME}"

# Step 4: Build
echo "[4/7] Building..."
dotnet build "${SDK_NAME}.slnx"

# Step 5: Sync docs
echo "[5/7] Syncing docs..."
autosdk docs sync . 2>/dev/null || true

# Step 6: Git init + commit
echo "[6/7] Initializing git and committing..."
git init
git add -A

GENERATED_COUNT=$(find "src/libs/${SDK_NAME}/Generated/" -type f | wc -l | tr -d ' ')
git commit -m "$(cat <<EOF
Initial ${SDK_NAME} SDK

Auto-generated C# SDK from ${SDK_NAME} OpenAPI spec.
${GENERATED_COUNT} generated files.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"

# Step 7: Create GitHub repo + push + set metadata
echo "[7/7] Creating GitHub repo and pushing..."
gh repo create "${ORG}/${SDK_NAME}" --public --source=. --push

# Convert semicolons to --add-topic flags
TOPIC_FLAGS=""
IFS=';' read -ra TAG_ARRAY <<< "$TAGS"
for tag in "${TAG_ARRAY[@]}"; do
    TOPIC_FLAGS="$TOPIC_FLAGS --add-topic $tag"
done

gh repo edit "${ORG}/${SDK_NAME}" \
    --description "C# SDK for ${SDK_NAME} | Generated from OpenAPI" \
    --homepage "https://tryagi.github.io/${SDK_NAME}/" \
    --allow-update-branch \
    --enable-auto-merge \
    --delete-branch-on-merge \
    $TOPIC_FLAGS

echo ""
echo "=== Done! ==="
echo "Repository: https://github.com/${ORG}/${SDK_NAME}"
echo "Generated files: ${GENERATED_COUNT}"
echo ""
echo "Next steps:"
echo "  1. Customize generate.sh if auth scheme needs fixing (apiKey→bearer)"
echo "  2. Update Tests.cs with proper env var name"
echo "  3. Add example tests in Examples/"
echo "  4. Create CLAUDE.md with project overview"
echo "  5. Add MEAI interface if applicable"
