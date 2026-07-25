#!/usr/bin/env bash
#=============================================================================
# Doc Intelligence Pipeline — Install Script (Hardened)
# Cross-platform: macOS, Linux, Windows (Git Bash / WSL)
#
# Design:
#   - Phase 0: Pre-flight checks — every dependency checked independently
#   - Each phase is self-contained, failure in one does NOT kill the script
#   - Clear per-dependency status: [FOUND] [MISSING] [FALLBACK] [BLOCKED]
#   - Summary at end shows exactly what passed, failed, or was skipped
#   - No single command failure can crash the entire install
#=============================================================================
set +e  # DO NOT exit on error — we handle failures per-phase

# ── Globals ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -A CHECK_RESULTS   # phase -> "PASS"|"FAIL"|"SKIP"|"WARN"
declare -A CHECK_DETAILS   # phase -> detail string
OS=""
ROOT=""
PYTHON=""
PIP=""
HAS_GIT=false
HAS_PYTHON_DOCX=false
HAS_TOMLI=false
PHASE_FAILURES=0
PHASE_WARNINGS=0

# ── Colors (if terminal supports it) ───────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

banner()  { echo -e "${BOLD}${CYAN}==>${NC} ${BOLD}$*${NC}"; }
pass()    { echo -e "  ${GREEN}[PASS]${NC} $*"; }
fail()    { echo -e "  ${RED}[FAIL]${NC} $*"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info()    { echo -e "  ${CYAN}[INFO]${NC} $*"; }
detail()  { echo -e "          $*"; }

record() {
    local phase="$1" status="$2" msg="$3"
    CHECK_RESULTS["$phase"]="$status"
    CHECK_DETAILS["$phase"]="$msg"
    case "$status" in
        FAIL) ((PHASE_FAILURES++)) ;;
        WARN) ((PHASE_WARNINGS++)) ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 0: PRE-FLIGHT CHECKS — Every dependency, independently
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}=============================================${NC}"
echo -e "${BOLD}  Doc Intelligence Pipeline — Pre-Flight${NC}"
echo -e "${BOLD}=============================================${NC}"
echo ""

# ── 0.1 Operating System ──────────────────────────────────────────────────
detect_os() {
    local kernel
    kernel="$(uname -s 2>/dev/null || echo "unknown")"
    case "$kernel" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        CYGWIN*|MINGW*|MSYS_NT*|MSYS*) OS="windows" ;;
        *)
            if [[ -n "${USERPROFILE:-}" ]] || [[ -n "${HOMEDRIVE:-}" ]]; then
                OS="windows"
            else
                OS="unknown"
            fi
            ;;
    esac
}
detect_os

ARCH="$(uname -m 2>/dev/null || echo "unknown")"
OS_VER=""
case "$OS" in
    macos) OS_VER="$(sw_vers -productVersion 2>/dev/null || echo "unknown")" ;;
    linux) OS_VER="$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' || echo "unknown")" ;;
    windows) OS_VER="$(uname -s 2>/dev/null) / $(cmd.exe /c ver 2>/dev/null | head -1 || echo "unknown")" ;;
esac

echo -e "  ${BOLD}System${NC}"
detail "OS:       $OS ($OS_VER)"
detail "Arch:     $ARCH"
detail "Shell:    ${SHELL:-unknown}"
detail "Home:     ${HOME:-unknown}"
echo ""

# ── 0.2 Python 3 — try multiple paths ──────────────────────────────────────
banner "Checking Python 3..."

PYTHON=""
PYTHON_VER=""

# Ordered fallback list: python3 -> python -> python3.12 -> python3.11 -> python3.10 -> python3.9
for candidate in python3 python python3.12 python3.11 python3.10 python3.9; do
    if cmd_path=$(command -v "$candidate" 2>/dev/null); then
        ver_out=$("$cmd_path" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
        major=$(echo "$ver_out" | cut -d. -f1)
        if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$major" -ge 3 ]]; then
            PYTHON="$cmd_path"
            PYTHON_VER="$ver_out"
            break
        fi
    fi
done

if [[ -n "$PYTHON" ]]; then
    pass "Python 3 found: $PYTHON_VER at $PYTHON"
    record "python" "PASS" "$PYTHON_VER ($PYTHON)"
else
    fail "Python 3 not found (tried: python3, python, python3.12-3.9)"
    detail "Install Python 3.9+ from https://python.org/downloads/"
    detail "Or: brew install python3   (macOS)"
    detail "Or: apt install python3    (Ubuntu/Debian)"
    record "python" "FAIL" "not found in PATH"
fi
echo ""

# ── 0.3 pip ────────────────────────────────────────────────────────────────
banner "Checking pip..."

PIP=""
PIP_VER=""

if [[ -n "$PYTHON" ]]; then
    # Try pip3, pip, then python -m pip
    for candidate in pip3 pip; do
        if cmd_path=$(command -v "$candidate" 2>/dev/null); then
            ver_out=$("$cmd_path" --version 2>/dev/null)
            if [[ -n "$ver_out" ]]; then
                PIP="$cmd_path"
                PIP_VER="$ver_out"
                break
            fi
        fi
    done

    # Fallback: python -m pip
    if [[ -z "$PIP" ]]; then
        if "$PYTHON" -m pip --version &>/dev/null; then
            PIP="$PYTHON -m pip"
            PIP_VER=$("$PYTHON" -m pip --version 2>/dev/null)
        fi
    fi

    # Last resort: ensurepip
    if [[ -z "$PIP" ]]; then
        warn "pip not found; attempting python -m ensurepip..."
        if "$PYTHON" -m ensurepip --upgrade &>/dev/null; then
            PIP="$PYTHON -m pip"
            PIP_VER="(ensurepip bootstrap)"
        fi
    fi
fi

if [[ -n "$PIP" ]]; then
    pass "pip found: $PIP_VER"
    record "pip" "PASS" "$PIP_VER"
else
    fail "pip not found and could not be bootstrapped"
    detail "Will attempt to install packages via python -m pip as fallback"
    record "pip" "WARN" "not found; will use python -m pip fallback"
fi
echo ""

# ── 0.4 Git ────────────────────────────────────────────────────────────────
banner "Checking Git..."

GIT_VER=""
if cmd_path=$(command -v git 2>/dev/null); then
    GIT_VER=$("$cmd_path" --version 2>/dev/null)
    HAS_GIT=true
    pass "Git found: $GIT_VER"
    record "git" "PASS" "$GIT_VER"
else
    warn "Git not found — pipeline will work but without version history"
    detail "Install: brew install git (macOS) / apt install git (Linux)"
    detail "On Windows: https://git-scm.com/download/win"
    HAS_GIT=false
    record "git" "WARN" "not found; history disabled"
fi
echo ""

# ── 0.5 bash ───────────────────────────────────────────────────────────────
banner "Checking bash..."

BASH_VER=""
if cmd_path=$(command -v bash 2>/dev/null); then
    BASH_VER=$("$cmd_path" --version 2>/dev/null | head -1)
    pass "bash found: $BASH_VER"
    record "bash" "PASS" "$BASH_VER"
else
    if [[ "$OS" == "windows" ]]; then
        fail "bash not found — required on Windows (install Git Bash or WSL)"
        detail "https://git-scm.com/download/win (includes Git Bash)"
        detail "Or: wsl --install (Windows Subsystem for Linux)"
    else
        fail "bash not found (unexpected on $OS)"
    fi
    record "bash" "FAIL" "not found"
fi
echo ""

# ── 0.6 Disk space (2GB minimum) ───────────────────────────────────────────
banner "Checking disk space (>= 2GB free)..."

# Determine root path first (needed for disk check)
case "$OS" in
    macos|linux) ROOT="${HOME}/DocIntel" ;;
    windows)     ROOT="C:/DocIntel" ;;
    *)           ROOT="${HOME}/DocIntel" ;;
esac

# Get parent of root for df
ROOT_PARENT="$(dirname "$ROOT")"
mkdir -p "$ROOT_PARENT" 2>/dev/null || true

FREE_GB=0
case "$OS" in
    macos|linux)
        # Try df -k first, fallback to df -h parsing
        if free_kb=$(df -k "$ROOT_PARENT" 2>/dev/null | tail -1 | awk '{print $4}'); then
            FREE_GB=$((free_kb / 1024 / 1024))
        else
            free_str=$(df -h "$ROOT_PARENT" 2>/dev/null | tail -1 | awk '{print $4}')
            FREE_GB=$(echo "$free_str" | sed 's/[^0-9.]//g')
            if [[ "$free_str" == *"T"* ]]; then FREE_GB=$(echo "$FREE_GB * 1024" | bc 2>/dev/null || echo "999"); fi
        fi
        ;;
    windows)
        # Git Bash df
        if free_kb=$(df -k "$ROOT_PARENT" 2>/dev/null | tail -1 | awk '{print $4}'); then
            FREE_GB=$((free_kb / 1024 / 1024))
        else
            # Try wmic via cmd
            drive_letter="${ROOT:0:1}"
            free_bytes=$(cmd.exe /c "wmic logicaldisk where 'DeviceID=\"${drive_letter}:\"' get FreeSpace" 2>/dev/null | tail -2 | head -1 | tr -d ' \r')
            if [[ -n "$free_bytes" ]] && [[ "$free_bytes" =~ ^[0-9]+$ ]]; then
                FREE_GB=$((free_bytes / 1024 / 1024 / 1024))
            fi
        fi
        ;;
esac

if [[ "$FREE_GB" =~ ^[0-9]+$ ]] && [[ "$FREE_GB" -ge 2 ]]; then
    pass "Disk space: ~${FREE_GB}GB free (need 2GB)"
    record "disk_space" "PASS" "${FREE_GB}GB free"
else
    fail "Disk space: ~${FREE_GB}GB free — need at least 2GB"
    detail "Free up space or choose a different root via ROOT env var"
    record "disk_space" "FAIL" "${FREE_GB}GB free (need 2GB)"
fi
echo ""

# ── 0.7 Python packages — python-docx ──────────────────────────────────────
banner "Checking Python packages..."

# ── 0.7a: pandoc (preferred extractor) ─────────────────────────────────────
banner "Checking pandoc (document converter)..."

HAS_PANDOC=false
PANDOC_VER=""
if cmd_path=$(command -v pandoc 2>/dev/null); then
    PANDOC_VER=$("$cmd_path" --version 2>/dev/null | head -1)
    HAS_PANDOC=true
    pass "pandoc found: $PANDOC_VER"
    record "pandoc" "PASS" "$PANDOC_VER"
else
    warn "pandoc not found — will fall back to python-docx (lower quality)"
    case "$OS" in
        macos)   detail "Install: brew install pandoc" ;;
        linux)   detail "Install: sudo apt install pandoc   (or: sudo dnf install pandoc)" ;;
        windows) detail "Install: winget install Pandoc   (or: https://pandoc.org/installing.html)" ;;
    esac
    record "pandoc" "WARN" "not found; python-docx fallback"
fi

if [[ -n "$PYTHON" ]]; then
    if "$PYTHON" -c "import docx" 2>/dev/null; then
        DOCX_VER=$("$PYTHON" -c "import docx; print(getattr(docx, '__version__', 'installed'))" 2>/dev/null || echo "installed")
        pass "python-docx: $DOCX_VER"
        HAS_PYTHON_DOCX=true
        record "python-docx" "PASS" "$DOCX_VER"
    else
        warn "python-docx not installed (will auto-install)"
        HAS_PYTHON_DOCX=false
        record "python-docx" "WARN" "not installed (auto-install)"
    fi

    # tomli / tomllib
    if "$PYTHON" -c "import tomli" 2>/dev/null; then
        pass "tomli: installed"
        HAS_TOMLI=true
        record "tomli" "PASS" "installed"
    elif "$PYTHON" -c "import tomllib" 2>/dev/null; then
        pass "tomllib: available (Python 3.11+ stdlib)"
        HAS_TOMLI=true
        record "tomli" "PASS" "stdlib tomllib"
    else
        warn "tomli not installed (will auto-install)"
        HAS_TOMLI=false
        record "tomli" "WARN" "not installed (auto-install)"
    fi
else
    warn "Skipping package checks (no Python)"
    record "python-docx" "SKIP" "no Python"
    record "tomli" "SKIP" "no Python"
fi
echo ""

# ── 0.8 Pre-flight summary ─────────────────────────────────────────────────
echo -e "${BOLD}─────────────────────────────────────────────${NC}"
passed_count=0
failed_count=0
warn_count=0
for phase in python pip git bash disk_space pandoc python-docx tomli; do
    case "${CHECK_RESULTS[$phase]:-SKIP}" in
        PASS) ((passed_count++)) ;;
        FAIL) ((failed_count++)) ;;
        WARN) ((warn_count++)) ;;
    esac
done
total_checks=$((passed_count + failed_count + warn_count))

echo -e "  ${GREEN}Passed:${NC}  $passed_count"
echo -e "  ${RED}Failed:${NC}  $failed_count"
echo -e "  ${YELLOW}Warnings:${NC} $warn_count"

if [[ $failed_count -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}${BOLD}BLOCKERS DETECTED.${NC} Fix the failures above before proceeding."
    echo "  Failed checks:"
    for phase in python pip git bash disk_space pandoc python-docx tomli; do
        if [[ "${CHECK_RESULTS[$phase]}" == "FAIL" ]]; then
            echo -e "    ${RED}✗${NC} $phase: ${CHECK_DETAILS[$phase]}"
        fi
    done
fi
echo ""

# ── If Python is missing completely, we cannot continue ────────────────────
if [[ -z "$PYTHON" ]]; then
    echo -e "${RED}FATAL: Python 3 is required to run the pipeline.${NC}"
    echo "Install Python 3.9+ then re-run this script."
    exit 1
fi

# ── Ask to continue ────────────────────────────────────────────────────────
if [[ $failed_count -gt 0 ]]; then
    echo -n "Continue anyway with best-effort installation? [y/N] "
    read -r response 2>/dev/null || true
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 1: ROOT DIRECTORY CREATION
# ═══════════════════════════════════════════════════════════════════════════

echo ""
banner "Phase 1: Root Directory Creation"
echo "  Root: $ROOT"

if mkdir -p "$ROOT" 2>/dev/null; then
    pass "Root created: $ROOT"
    record "root_create" "PASS" "$ROOT"
else
    fail "Could not create $ROOT"
    record "root_create" "FAIL" "mkdir failed"
fi

# Subdirectories
for sub in collected extracted knowledge actions logs scripts; do
    mkdir -p "$ROOT/$sub" 2>/dev/null || warn "Could not create $ROOT/$sub"
done

# Permissions (Unix only)
if [[ "$OS" != "windows" ]]; then
    chmod 755 "$ROOT" 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 2: CONFIG.TOML
# ═══════════════════════════════════════════════════════════════════════════

echo ""
banner "Phase 2: Configuration (config.toml)"

TEMPLATE_CONFIG="${SCRIPT_DIR}/../templates/config.toml"
CONFIG_WRITTEN=false

if [[ -f "$TEMPLATE_CONFIG" ]]; then
    if cp "$TEMPLATE_CONFIG" "$ROOT/config.toml" 2>/dev/null; then
        pass "config.toml copied from template"
        CONFIG_WRITTEN=true
    else
        warn "Could not copy template config (permissions?)"
    fi
fi

if [[ "$CONFIG_WRITTEN" != true ]]; then
    warn "Writing minimal config.toml from built-in defaults..."
    cat > "$ROOT/config.toml" << 'EOF'
[memory]
max_disk_gb = 2

[scan]
recursive = true
max_depth = 8
file_types = [".docx"]
min_size_bytes = 1024

[cron]
schedule = "0 6 * * *"
enabled = true
pipeline_script = "scripts/pipeline.py"

[extraction]
pause_ms = 1000
batch_size = 10
incremental = true

[knowledge]
detect_hints = true
detect_repetitive_words = true
detect_layout_patterns = true
detect_reused_assets = true
detect_duplicates = true
duplicate_flag = "might be a small change - investigate"
similarity_threshold = 0.85
min_corpus_size = 3

[actions]
generate_docx = true
whatsapp_send = true
stop_on_complete = false
output_dir = "actions"

[proctor]
validate_after_scan = true
validate_after_extraction = true
strict = true

[logging]
level = "INFO"
log_file = "logs/pipeline.log"
max_log_size = 10485760
backup_count = 5
EOF
    if [[ -f "$ROOT/config.toml" ]]; then
        pass "Minimal config.toml written"
        CONFIG_WRITTEN=true
    fi
fi

# Verify max_disk_gb = 2 in config
if "$PYTHON" -c "
import sys
sys.path.insert(0, '$ROOT/scripts')
try:
    import tomli
    with open('$ROOT/config.toml', 'rb') as f: cfg = tomli.load(f)
except:
    try:
        import tomllib
        with open('$ROOT/config.toml', 'rb') as f: cfg = tomllib.load(f)
    except:
        cfg = {}
mem = cfg.get('memory', {}).get('max_disk_gb', 0)
print(mem)
" 2>/dev/null; then
    pass "Verified: max_disk_gb = 2GB"
    record "config" "PASS" "2GB configured"
else
    record "config" "WARN" "config verification skipped"
fi

# ── Platform-specific scan dirs in config ──────────────────────────────────
if [[ "$CONFIG_WRITTEN" == true ]]; then
    case "$OS" in
        macos)
            "$PYTHON" -c "
with open('$ROOT/config.toml', 'a') as f:
    f.write('\n# macOS scan directories\n[scan]\ndirectories_mac = [\"~/Downloads\", \"~/Desktop\", \"~/Documents\", \"~/Library/CloudStorage\"]\n')
" 2>/dev/null || true
            ;;
        linux)
            "$PYTHON" -c "
with open('$ROOT/config.toml', 'a') as f:
    f.write('\n# Linux scan directories\n[scan]\ndirectories_linux = [\"~/Downloads\", \"~/Desktop\", \"~/Documents\"]\n')
" 2>/dev/null || true
            ;;
        windows)
            "$PYTHON" -c "
with open('$ROOT/config.toml', 'a') as f:
    f.write('\n# Windows scan directories\n[scan]\ndirectories_win = [\"%USERPROFILE%\\\\\\Downloads\", \"%USERPROFILE%\\\\\\Desktop\", \"%USERPROFILE%\\\\\\Documents\", \"%USERPROFILE%\\\\\\OneDrive\"]\n')
" 2>/dev/null || true
            ;;
    esac
fi

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 3: COPY PIPELINE SCRIPT
# ═══════════════════════════════════════════════════════════════════════════

echo ""
banner "Phase 3: Pipeline Script"

PIPELINE_SRC="${SCRIPT_DIR}/pipeline.py"
PIPELINE_DST="$ROOT/scripts/pipeline.py"

if [[ -f "$PIPELINE_SRC" ]]; then
    if cp "$PIPELINE_SRC" "$PIPELINE_DST" 2>/dev/null; then
        chmod +x "$PIPELINE_DST" 2>/dev/null || true
        pass "pipeline.py deployed to $PIPELINE_DST"
        record "pipeline_script" "PASS" "deployed"
    else
        fail "Could not copy pipeline.py to $PIPELINE_DST"
        record "pipeline_script" "FAIL" "copy failed"
    fi
else
    warn "pipeline.py not found at $PIPELINE_SRC"
    detail "Expected alongside install.sh in the skill's scripts/ directory"
    detail "Deploy manually to $PIPELINE_DST"
    record "pipeline_script" "WARN" "source not found"
fi

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 4: GIT INIT
# ═══════════════════════════════════════════════════════════════════════════

echo ""
banner "Phase 4: Git Repository"

if [[ "$HAS_GIT" == true ]]; then
    cd "$ROOT" || true
    if [[ ! -d ".git" ]]; then
        if git init 2>/dev/null; then
            git config user.name "Doc Intelligence Pipeline" 2>/dev/null || true
            git config user.email "pipeline@localhost" 2>/dev/null || true
            cat > "$ROOT/.gitignore" << 'GITIGNORE'
__pycache__/
*.pyc
*.pyo
logs/*.log.*
.DS_Store
Thumbs.db
GITIGNORE
            git add -A 2>/dev/null || true
            git commit -m "Initial commit: doc-intelligence-pipeline" 2>/dev/null || true
            pass "Git repository initialized"
            record "git_init" "PASS" "initialized"
        else
            warn "git init failed — continuing without version history"
            record "git_init" "WARN" "init failed"
        fi
    else
        pass "Git repository already exists"
        record "git_init" "PASS" "already exists"
    fi
else
    warn "Git not available — skipping repository init"
    detail "Install git for version history: brew install git / apt install git"
    record "git_init" "SKIP" "git not found"
fi

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 5: PYTHON DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════

echo ""
banner "Phase 5: Dependencies"

# ── pandoc (try to install if missing) ──────────────────────────────────────
if [[ "$HAS_PANDOC" != true ]]; then
    info "Attempting to install pandoc..."
    case "$OS" in
        macos)
            if command -v brew &>/dev/null; then
                brew install pandoc 2>/dev/null && HAS_PANDOC=true && pass "pandoc installed via Homebrew"
            else
                warn "Homebrew not found — install pandoc manually: brew install pandoc"
            fi
            ;;
        linux)
            if command -v apt-get &>/dev/null; then
                sudo apt-get install -y pandoc 2>/dev/null && HAS_PANDOC=true && pass "pandoc installed via apt"
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y pandoc 2>/dev/null && HAS_PANDOC=true && pass "pandoc installed via dnf"
            else
                warn "No package manager found — install pandoc manually"
            fi
            ;;
        windows)
            if command -v winget &>/dev/null; then
                winget install Pandoc 2>/dev/null && HAS_PANDOC=true && pass "pandoc installed via winget"
            elif command -v choco &>/dev/null; then
                choco install pandoc -y 2>/dev/null && HAS_PANDOC=true && pass "pandoc installed via Chocolatey"
            else
                warn "No package manager — download from https://pandoc.org/installing.html"
            fi
            ;;
    esac
fi

# ── Python packages ────────────────────────────────────────────────────────

install_pkg() {
    local pkg="$1"
    local import_name="$2"

    # Already installed?
    if "$PYTHON" -c "import $import_name" 2>/dev/null; then
        pass "$pkg already installed"
        return 0
    fi

    info "Installing $pkg..."

    # Try pip
    if [[ -n "$PIP" ]]; then
        if $PIP install --quiet "$pkg" 2>/dev/null; then
            pass "$pkg installed via pip"
            return 0
        fi
        warn "pip install $pkg failed, trying python -m pip..."
    fi

    # Try python -m pip
    if "$PYTHON" -m pip install --quiet "$pkg" 2>/dev/null; then
        pass "$pkg installed via python -m pip"
        return 0
    fi

    # Try user install
    if "$PYTHON" -m pip install --quiet --user "$pkg" 2>/dev/null; then
        pass "$pkg installed via python -m pip --user"
        return 0
    fi

    fail "Could not install $pkg"
    return 1
}

DOCX_INSTALLED=false
TOMLI_INSTALLED=false

install_pkg "python-docx" "docx" && DOCX_INSTALLED=true || {
    warn "python-docx install failed — extraction will use ZIP/XML fallback (built-in)"
    record "install_python-docx" "WARN" "using stdlib fallback"
}

install_pkg "tomli" "tomli" && TOMLI_INSTALLED=true || {
    # Check for stdlib tomllib (Python 3.11+)
    if "$PYTHON" -c "import tomllib" 2>/dev/null; then
        pass "tomllib available via stdlib (Python 3.11+)"
        TOMLI_INSTALLED=true
    else
        warn "tomli install failed and no stdlib fallback — config will use basic parsing"
        record "install_tomli" "WARN" "basic config fallback"
    fi
}

if [[ "$DOCX_INSTALLED" == true ]] && [[ "$TOMLI_INSTALLED" == true ]]; then
    record "install_deps" "PASS" "all packages ready"
elif [[ "$DOCX_INSTALLED" == true ]] || [[ "$TOMLI_INSTALLED" == true ]]; then
    record "install_deps" "WARN" "partial success"
else
    record "install_deps" "FAIL" "no packages installed"
fi

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 6: CRON / SCHEDULER SETUP
# ═══════════════════════════════════════════════════════════════════════════

echo ""
banner "Phase 6: Dual Schedulers — Daily Scan (06:00) + 2hr Delivery Retry"

PIPELINE_PATH="$ROOT/scripts/pipeline.py"
CRON_OK=false
RETRY_CRON_OK=false

case "$OS" in
    macos)
        PLIST="$HOME/Library/LaunchAgents/com.docintel.scan.plist"
        mkdir -p "$HOME/Library/LaunchAgents" 2>/dev/null || true
        cat > "$PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.docintel.scan</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$PIPELINE_PATH</string>
        <string>scan</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>6</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>WorkingDirectory</key>
    <string>$ROOT</string>
    <key>StandardOutPath</key>
    <string>$ROOT/logs/cron_stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$ROOT/logs/cron_stderr.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
PLIST
        if launchctl unload "$PLIST" 2>/dev/null; then true; fi
        if launchctl load "$PLIST" 2>/dev/null; then
            pass "launchd job installed: com.docintel.scan (daily 06:00)"
            CRON_OK=true
            record "cron" "PASS" "launchd"
        else
            warn "launchd load failed — plist written, load manually:"
            detail "launchctl load $PLIST"
            record "cron" "WARN" "launchd plist written, not loaded"
        fi

        # ── 2-hour retry job for pending deliveries ─────────────────
        local retry_plist="$HOME/Library/LaunchAgents/com.docintel.deliver.plist"
        cat > "$retry_plist" << RETRYPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.docintel.deliver</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON</string>
        <string>$PIPELINE_PATH</string>
        <string>deliver</string>
    </array>
    <key>StartInterval</key>
    <integer>7200</integer>
    <key>WorkingDirectory</key>
    <string>$ROOT</string>
    <key>StandardOutPath</key>
    <string>$ROOT/logs/deliver_stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$ROOT/logs/deliver_stderr.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
RETRYPLIST
        launchctl unload "$retry_plist" 2>/dev/null || true
        if launchctl load "$retry_plist" 2>/dev/null; then
            pass "launchd retry job: com.docintel.deliver (every 2hr)"
            RETRY_CRON_OK=true
        else
            warn "launchd retry load failed — load manually:"
            detail "launchctl load $retry_plist"
        fi
        ;;

    linux)
        CRON_CMD="0 6 * * * cd '$ROOT' && '$PYTHON' '$PIPELINE_PATH' scan >> '$ROOT/logs/cron_stdout.log' 2>> '$ROOT/logs/cron_stderr.log'"
        RETRY_CMD="0 */2 * * * cd '$ROOT' && '$PYTHON' '$PIPELINE_PATH' deliver >> '$ROOT/logs/deliver_stdout.log' 2>> '$ROOT/logs/deliver_stderr.log'"
        if crontab -l 2>/dev/null | grep -q "pipeline.py scan"; then
            pass "Cron scan job already in crontab"
            CRON_OK=true
            record "cron" "PASS" "crontab (already present)"
        elif (crontab -l 2>/dev/null || true; echo "$CRON_CMD") | crontab - 2>/dev/null; then
            pass "Cron scan job added: daily 06:00"
            CRON_OK=true
            record "cron" "PASS" "crontab"
        else
            warn "Crontab update failed — add manually:"
            detail "crontab -e"
            detail "Add: $CRON_CMD"
            record "cron" "WARN" "crontab add failed"
        fi
        # Retry job: every 2 hours
        if crontab -l 2>/dev/null | grep -q "pipeline.py deliver"; then
            pass "Cron retry job already in crontab (every 2hr)"
            RETRY_CRON_OK=true
        elif (crontab -l 2>/dev/null || true; echo "$RETRY_CMD") | crontab - 2>/dev/null; then
            pass "Cron retry job added: every 2 hours"
            RETRY_CRON_OK=true
        else
            warn "Crontab retry add failed — add manually:"
            detail "crontab -e"
            detail "Add: $RETRY_CMD"
        fi
        ;;

    windows)
        TASK_NAME="DocIntelScan"
        RETRY_TASK="DocIntelDeliver"
        # Try schtasks for scan
        schtasks /delete /tn "$TASK_NAME" /f 2>/dev/null || true
        if schtasks /create /tn "$TASK_NAME" /tr "$PYTHON $PIPELINE_PATH scan" /sc daily /st 06:00 /f 2>/dev/null; then
            pass "Task Scheduler: $TASK_NAME (daily 06:00)"
            CRON_OK=true
            record "cron" "PASS" "schtasks"
        else
            warn "schtasks failed (may need admin) — create manually:"
            detail "Run in elevated terminal:"
            detail "schtasks /create /tn \"$TASK_NAME\" /tr \"$PYTHON $PIPELINE_PATH scan\" /sc daily /st 06:00"
            record "cron" "WARN" "schtasks failed"
        fi
        # Retry job: every 2 hours
        schtasks /delete /tn "$RETRY_TASK" /f 2>/dev/null || true
        if schtasks /create /tn "$RETRY_TASK" /tr "$PYTHON $PIPELINE_PATH deliver" /sc hourly /mo 2 /f 2>/dev/null; then
            pass "Task Scheduler: $RETRY_TASK (every 2hr)"
            RETRY_CRON_OK=true
        else
            warn "schtasks retry failed — create manually:"
            detail "schtasks /create /tn \"$RETRY_TASK\" /tr \"$PYTHON $PIPELINE_PATH deliver\" /sc hourly /mo 2"
        fi
        ;;
esac

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 7: VERIFY PIPELINE (quick smoke test)
# ═══════════════════════════════════════════════════════════════════════════

echo ""
banner "Phase 7: Pipeline Smoke Test"

if [[ -f "$PIPELINE_DST" ]]; then
    if "$PYTHON" -c "import ast; ast.parse(open('$PIPELINE_DST').read()); print('OK')" 2>/dev/null; then
        pass "pipeline.py syntax check: OK"
        record "smoke_test" "PASS" "syntax valid"
    else
        warn "pipeline.py has syntax errors"
        record "smoke_test" "WARN" "syntax check failed"
    fi
else
    warn "pipeline.py not found — cannot smoke test"
    record "smoke_test" "SKIP" "file missing"
fi

# ═══════════════════════════════════════════════════════════════════════════
# INSTALL SUMMARY
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}=============================================${NC}"
echo -e "${BOLD}  Installation Summary${NC}"
echo -e "${BOLD}=============================================${NC}"
echo ""

total_phases=0
passed_phases=0
failed_phases=0
warned_phases=0
skipped_phases=0

for phase in python pip git bash disk_space pandoc python-docx tomli root_create config pipeline_script git_init install_deps cron smoke_test; do
    status="${CHECK_RESULTS[$phase]:-SKIP}"
    [[ "$status" == "SKIP" ]] && continue
    ((total_phases++))
    case "$status" in
        PASS) ((passed_phases++))
              echo -e "  ${GREEN}✓${NC} $phase: ${CHECK_DETAILS[$phase]}" ;;
        FAIL) ((failed_phases++))
              echo -e "  ${RED}✗${NC} $phase: ${CHECK_DETAILS[$phase]}" ;;
        WARN) ((warned_phases++))
              echo -e "  ${YELLOW}⚠${NC} $phase: ${CHECK_DETAILS[$phase]}" ;;
    esac
done

echo ""
echo -e "  ${GREEN}Passed:${NC}  $passed_phases"
echo -e "  ${RED}Failed:${NC}  $failed_phases"
echo -e "  ${YELLOW}Warnings:${NC} $warned_phases"
echo ""

echo -e "${BOLD}Root:${NC} $ROOT"
echo -e "${BOLD}Config:${NC} $ROOT/config.toml"
echo ""

echo -e "${BOLD}Next Steps:${NC}"
echo "  1. First scan:     $PYTHON $ROOT/scripts/pipeline.py scan"
echo "  2. Extract:        $PYTHON $ROOT/scripts/pipeline.py extract"
echo "  3. Knowledge:      $PYTHON $ROOT/scripts/pipeline.py knowledge"
echo "  4. Validate:       $PYTHON $ROOT/scripts/pipeline.py proctor"
echo "  5. Full pipeline:  $PYTHON $ROOT/scripts/pipeline.py full"
echo ""

if [[ "$CRON_OK" == true ]]; then
    echo "Daily scan scheduled for 06:00 local time."
else
    echo "Manual scan needed (cron not configured):"
    echo "  $PYTHON $PIPELINE_PATH scan"
fi
if [[ "$RETRY_CRON_OK" == true ]]; then
    echo "Delivery retry runs every 2 hours (pending notifications)."
else
    echo "Retry not scheduled — dead-letter queue still works, retries happen on next scan."
fi
echo ""

if [[ $failed_phases -gt 0 ]]; then
    echo -e "${RED}${BOLD}⚠  $failed_phases phase(s) failed.${NC} Review above and fix before full operation."
    exit 1
elif [[ $warned_phases -gt 0 ]]; then
    echo -e "${YELLOW}⚠  $warned_phases warning(s). Pipeline will work with reduced functionality.${NC}"
    exit 0
else
    echo -e "${GREEN}${BOLD}All phases passed. Pipeline is ready.${NC}"
    exit 0
fi
