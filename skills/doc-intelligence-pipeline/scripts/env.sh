#!/usr/bin/env bash
#=============================================================================
# Doc Intelligence Pipeline — Environment Setup (sourceable)
#
# Source this file to set ROOT, PYTHON, and CONFIG_PATH in your current shell.
# Usage: source scripts/env.sh
#
# This is the lightweight alternative to install.sh — no root creation,
# no git init, no cron setup. Just detect OS and export the right paths.
#=============================================================================

# ── OS Detection ───────────────────────────────────────────────────────────
_docintel_detect_os() {
    local kernel
    kernel="$(uname -s 2>/dev/null || echo "unknown")"
    case "$kernel" in
        Darwin)                echo "macos" ;;
        Linux)                 echo "linux" ;;
        CYGWIN*|MINGW*|MSYS*)  echo "windows" ;;
        *)                     echo "unknown" ;;
    esac
}

DOCINTEL_OS="$(_docintel_detect_os)"
export DOCINTEL_OS

# ── Root path per platform ─────────────────────────────────────────────────
case "$DOCINTEL_OS" in
    macos|linux)
        DOCINTEL_ROOT="${DOCINTEL_ROOT:-${HOME}/DocIntel}"
        ;;
    windows)
        DOCINTEL_ROOT="${DOCINTEL_ROOT:-C:/DocIntel}"
        ;;
    *)
        DOCINTEL_ROOT="${DOCINTEL_ROOT:-${HOME}/DocIntel}"
        ;;
esac
export DOCINTEL_ROOT

# ── Python detection ───────────────────────────────────────────────────────
_docintel_find_python() {
    for candidate in python3 python python3.12 python3.11 python3.10 python3.9; do
        if cmd_path=$(command -v "$candidate" 2>/dev/null); then
            ver_out=$("$cmd_path" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
            major=$(echo "$ver_out" | cut -d. -f1)
            if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -ge 3 ]]; then
                echo "$cmd_path"
                return 0
            fi
        fi
    done
    echo ""
    return 1
}

DOCINTEL_PYTHON="${DOCINTEL_PYTHON:-$(_docintel_find_python)}"
export DOCINTEL_PYTHON

# ── Config path ────────────────────────────────────────────────────────────
DOCINTEL_CONFIG="${DOCINTEL_ROOT}/config.toml"
export DOCINTEL_CONFIG

# ── Print summary ──────────────────────────────────────────────────────────
if [[ "${DOCINTEL_QUIET:-}" != "1" ]]; then
    echo "DocIntel environment:"
    echo "  OS:      $DOCINTEL_OS"
    echo "  ROOT:    $DOCINTEL_ROOT"
    echo "  PYTHON:  ${DOCINTEL_PYTHON:-NOT FOUND}"
    echo "  CONFIG:  $DOCINTEL_CONFIG"
    echo ""
    if [[ -z "$DOCINTEL_PYTHON" ]]; then
        echo "  WARNING: Python 3 not found. Install Python 3.9+ first."
    fi
    if [[ ! -f "$DOCINTEL_CONFIG" ]]; then
        echo "  WARNING: config.toml not found. Run install.sh or create manually."
    fi
fi

# ── Cleanup internal functions ─────────────────────────────────────────────
unset -f _docintel_detect_os _docintel_find_python
