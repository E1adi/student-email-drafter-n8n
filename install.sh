#!/bin/bash
# install.sh — sets up Docker + n8n + extractor sidecar on macOS
set -e

echo "==> Checking Homebrew..."
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for Apple Silicon
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
fi

echo "==> Checking git..."
if ! command -v git &>/dev/null; then
  echo "Installing git..."
  brew install git
fi

echo "==> Checking Docker..."
if ! command -v docker &>/dev/null; then
  echo "Installing Docker Desktop via Homebrew..."
  brew install --cask docker
  echo ""
  echo "  ⚠️  Docker Desktop installed. Open it from /Applications to start the daemon,"
  echo "  then re-run this script."
  exit 0
fi

# Wait for Docker daemon
echo "==> Waiting for Docker daemon..."
for i in $(seq 1 15); do
  docker info &>/dev/null && break
  echo "   ...not ready yet ($i/15), waiting 3s"
  sleep 3
done
docker info &>/dev/null || { echo "Docker daemon not running. Open Docker Desktop and retry."; exit 1; }

echo "==> Checking .env..."
if [ ! -f .env ]; then
  cp .env.example .env
  echo ""
  echo "  ✏️  .env created from .env.example"
  echo "  Edit .env and set your LLM_API_KEY (Gemini key from https://aistudio.google.com/app/apikey),"
  echo "  then re-run this script."
  exit 0
fi

# Merge any keys from .env.example that are missing from .env (preserves existing values)
echo "==> Syncing new keys from .env.example into .env..."
while IFS= read -r line; do
  # Skip comments and blank lines
  [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
  key="${line%%=*}"
  if ! grep -q "^${key}=" .env; then
    echo "$line" >> .env
    echo "  Added missing key: $key"
  fi
done < .env.example

# Verify Gemini key is set
if grep -q "^LLM_API_KEY=your_gemini_api_key_here" .env; then
  echo "  ⚠️  Set your real LLM_API_KEY in .env first."
  echo "  Get a free Gemini key at: https://aistudio.google.com/app/apikey"
  exit 1
fi

echo "==> Creating files/ folders..."
mkdir -p files/assignments files/reviews

if [ ! -f files/email_template.md ]; then
  cp email_template.example.md files/email_template.md
  echo "  Created files/email_template.md (edit to customise)"
fi

echo "==> Building and starting services..."
docker compose up -d --build

echo ""
echo "✅ Done!"
echo ""
echo "  n8n:       http://localhost:5678"
echo ""
echo "Next steps:"
echo "  1. Drop assignment PDFs/DOCXs into: files/assignments/"
echo "  2. Drop review DOCXs into:          files/reviews/"
echo "  3. Add your class roster to:        files/roster.xlsx"
echo "  4. (Optional) Edit email template:  files/email_template.md"
echo ""
echo "  5. Set up Gmail OAuth2 — see README.md § Configure Gmail OAuth2"
echo "  6. Open http://localhost:5678 → Import workflow.json"
echo "  7. Open Create Gmail Draft node → set Gmail credential"
echo "  8. Click 'Test workflow'"
