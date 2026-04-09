#!/bin/bash
# db-skill setup script
# Usage: bash setup.sh

set -e

echo "=== db-skill setup ==="
echo ""

# 1. OS 감지
detect_os() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    Darwin*)              echo "macos" ;;
    Linux*)               echo "linux" ;;
    *)                    echo "unknown" ;;
  esac
}

OS=$(detect_os)
echo "[1/3] OS detected: ${OS}"

# 2. usql 설치 확인
if command -v usql &>/dev/null; then
  echo "[2/3] usql already installed: $(usql --version 2>&1 | head -1)"
else
  echo "[2/3] usql not found. Installing..."
  case "$OS" in
    windows)
      if command -v scoop &>/dev/null; then
        scoop install usql
      else
        echo "  scoop not found. Install manually:"
        echo "    scoop install usql"
        echo "  or: go install github.com/xo/usql@latest"
        exit 1
      fi
      ;;
    macos)
      if command -v brew &>/dev/null; then
        brew install xo/xo/usql
      else
        echo "  brew not found. Install manually:"
        echo "    go install github.com/xo/usql@latest"
        exit 1
      fi
      ;;
    linux)
      if command -v go &>/dev/null; then
        go install github.com/xo/usql@latest
      elif command -v brew &>/dev/null; then
        brew install xo/xo/usql
      else
        echo "  go or brew required. Install manually:"
        echo "    go install github.com/xo/usql@latest"
        exit 1
      fi
      ;;
    *)
      echo "  Unsupported OS. Install usql manually:"
      echo "    https://github.com/xo/usql"
      exit 1
      ;;
  esac
  echo "  usql installed: $(usql --version 2>&1 | head -1)"
fi

# 3. DB 프로파일 디렉토리 생성
DB_DIR="${HOME}/.claude/db"
SCHEMA_DIR="${DB_DIR}/schema"

mkdir -p "${DB_DIR}" "${SCHEMA_DIR}"

# 예제 프로파일 복사 (없을 때만)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "${DB_DIR}/example.mariadb.dev.env" ]; then
  cp "${SCRIPT_DIR}/db/example.mariadb.dev.env" "${DB_DIR}/"
  echo "[3/3] Example profile created: ${DB_DIR}/example.mariadb.dev.env"
else
  echo "[3/3] Profile directory ready: ${DB_DIR}/"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. cp ${DB_DIR}/example.mariadb.dev.env ${DB_DIR}/{project}.{db}.{env}.env"
echo "  2. Edit the new .env file with your connection details"
echo "  3. Use /db list, /db query, /db schema dump in Claude Code"
