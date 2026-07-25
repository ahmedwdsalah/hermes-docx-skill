---
name: doc-intelligence-pipeline
description: "Cross-OS .docx scanner: 2GB, cron, knowledge extraction."
version: 1.1.0
author: Ahmed + Hermes
license: MIT
platforms: [macos, windows, linux]
prerequisites:
  commands: [python3, git, bash]
  python_packages: [python-docx, tomli]
metadata:
  hermes:
    tags: [document, docx, intelligence, pipeline, extraction, knowledge, cross-platform]
    related_skills: [hermes-agent]
---

# Doc Intelligence Pipeline

A shippable, cross-platform skill that sets up a complete document intelligence pipeline on any machine (Windows, macOS, or Linux). It scans the system directory-by-directory for Word documents, extracts knowledge patterns, and builds actionable intelligence -- all running on a cron schedule.

## Overview

This skill contains everything needed to deploy the pipeline:

| File | Role |
|------|------|
| `scripts/install.sh` | OS detection, root creation, git init, dependency install, cron setup |
| `scripts/pipeline.py` | Scan -> collect -> parse -> extract -> knowledge -> proctor |
| `templates/config.toml` | Pipeline configuration (2GB memory, paths, scan dirs, extraction settings) |
| `references/cron-setup.md` | Platform-specific scheduler instructions (launchd / cron / Task Scheduler) |
| `scripts/env.sh` | Lightweight env setup: source to set ROOT, PYTHON, CONFIG_PATH |

### Quick Health Check

Run this on the target machine to see what needs attention before a full install:

```bash
# Copy-paste into terminal — detects OS and reports every dependency
echo "=== DocIntel Quick Health Check ==="
echo "OS: $(uname -s) $(uname -m)"
for cmd in python3 python git bash; do
  if command -v "$cmd" &>/dev/null; then
    ver=$("$cmd" --version 2>&1 | head -1)
    echo "  [OK]   $cmd — $ver"
  else
    echo "  [MISS] $cmd"
  fi
done
df -h "${HOME}" 2>/dev/null | tail -1 | awk '{printf "  [INFO] Disk: %s free\n", $4}'
echo "=== End Health Check ==="
```

If any `[MISS]` lines appear, fix those before running `install.sh`.  
If all `[OK]`, proceed: `bash scripts/install.sh`

## When to Use

Load this skill when:
- Deploying the doc-intelligence pipeline on a fresh machine
- The user says "set up doc intelligence", "scan my documents", "extract knowledge from Word files"
- You need to collect, parse, and extract patterns from .docx files across the system
- Setting up automated daily document scanning at 06:00

## Prerequisites — Dynamic Dependency Check

The install script (`scripts/install.sh`) runs a **pre-flight check** before any changes are made. Every dependency is checked independently — a missing tool does NOT block the entire install. The agent sees a clear report and can remediate before proceeding.

### Checked at runtime (Phase 0 of install.sh):

| Dependency | Minimum | Check Method | Fallback |
|-----------|---------|-------------|----------|
| **Python 3** | 3.9+ | `python3 --version` then `python --version` | Attempts `python3.11`, `python3.10`, `python3.9` in order |
| **pip** | any | `pip3 --version` then `pip --version` | Uses `python3 -m pip` as final fallback |
| **Git** | any | `git --version` | Warns but continues; pipeline works without git (no version history) |
| **Disk space** | 2GB free | `df` (Unix) / `wmic` or `df` (Windows) | Reports exact available space; blocks root creation if insufficient |
| **bash** | any | `bash --version` | Required on Windows (Git Bash, WSL); native on macOS/Linux |
| **python-docx** | any | `python3 -c "import docx"` | Auto-installed via pip during Phase 9 |
| **tomli** | any | `python3 -c "import tomli"` | Auto-installed via pip during Phase 9; Python 3.11+ has stdlib fallback |

### What the agent sees on a target machine:

```
=== Doc Intelligence Pipeline — Pre-Flight Checks ===
[CHECK] Operating System .............. macOS 26.5 (arm64)
[CHECK] Python 3 ...................... FOUND: Python 3.12.4
[CHECK] pip ........................... FOUND: pip 24.1
[CHECK] Git ........................... FOUND: git 2.45.0
[CHECK] bash .......................... FOUND: GNU bash 5.2
[CHECK] Disk space (2GB) .............. PASS: 234GB free
[CHECK] python-docx ................... NOT INSTALLED
[CHECK] tomli ......................... NOT INSTALLED
=== 6/8 checks satisfied, 2 will be auto-installed ===
```

### No single point of failure:

- **Git missing**: Pipeline runs without version history; `git commit` calls become no-ops
- **pip missing on Windows**: Script falls back to `python -m pip` or `python -m ensurepip`
- **python-docx fails to install**: Extraction falls back to ZIP + XML parsing (built into Python stdlib)
- **tomli fails to install**: Python 3.11+ uses stdlib `tomllib`; for older Python, `json` fallback reads a converted config
- **Cron setup fails** (permissions, missing schtasks): Manual instructions printed; pipeline still usable via `python3 pipeline.py scan`
- **Disk space < 2GB**: Root creation blocked, error message shows exact available space
- **Any single phase failure**: Script continues to next phase, prints summary of what passed/failed at end

## Architecture (9 Phases)

```
Phase 1: OS Detect    -> uname / ver -> set platform vars
Phase 2: Root Create  -> C:\DocIntel (Win) or ~/DocIntel (Mac/Linux)
Phase 3: Config       -> templates/config.toml -> root/config.toml (2GB memory allocated)
Phase 4: Git Init     -> git init in root (tracks all collected data)
Phase 5: Doc Scan     -> dir-by-dir sync walk -> collect .docx paths -> save index
Phase 6: Cron Setup   -> daily 06:00 scan of Downloads, Desktop, Documents + platform dirs
Phase 7: Parse Loop   -> wait 1000ms -> parse each .docx -> extract text
Phase 8: Knowledge    -> hints, repetitive words, layout, reused assets, duplicates
Phase 9: Actions + Proctor -> generate .docx, WhatsApp send, or stop -> validate pipeline
```

---

## Phase 1: OS Detection

The install script auto-detects the OS and shell environment. No user input needed.

**Detection logic (in scripts/install.sh):**

```bash
case "$(uname -s)" in
  Darwin)  OS="macos" ;;
  Linux)   OS="linux" ;;
  CYGWIN*|MINGW*|MSYS*) OS="windows" ;;
esac
```

On Windows (Git Bash / WSL), it also checks `$USERPROFILE` and `$HOMEDRIVE`.

The pipeline adapts:
- **Paths**: backslash on Windows cmd, forward slash everywhere else
- **Cron**: launchd (macOS), cron (Linux), schtasks (Windows)
- **Root**: `C:\DocIntel` on Windows, `~/DocIntel` on macOS/Linux
- **Python**: `python3` on Unix, `python` on Windows

---

## Phase 2: Root Directory Creation

The root is the pipeline's working directory -- it holds the config, git repo, collected file index, extracted knowledge, and action outputs.

| Platform | Root Path | Rationale |
|----------|-----------|-----------|
| Windows  | `C:\DocIntel` | Next to `C:\Users`, globally accessible |
| macOS    | `~/DocIntel` | User home, full read/write, no SIP issues |
| Linux    | `~/DocIntel` | User home, standard location |

The install script:
1. Checks available disk space (needs >= 2GB free)
2. Creates the root directory if it doesn't exist
3. Sets restrictive permissions (0700 on Unix)

---

## Phase 3: Configuration (config.toml)

The pipeline is driven by `config.toml` in the root. The install script copies `templates/config.toml` and adjusts platform-specific paths.

**Key settings:**

```toml
[memory]
max_disk_gb = 2              # 2GB allocation for pipeline storage

[scan]
directories_win  = ["C:\\Users\\*\\Downloads", "C:\\Users\\*\\Desktop", "C:\\Users\\*\\Documents"]
directories_mac  = ["~/Downloads", "~/Desktop", "~/Documents"]
directories_linux = ["~/Downloads", "~/Desktop", "~/Documents"]
recursive = true
max_depth = 8                 # safety cap
file_types = [".docx"]

[cron]
schedule = "0 6 * * *"       # daily at 06:00 local time

[extraction]
pause_ms = 1000              # wait between batch parses
batch_size = 10              # files per batch

[knowledge]
detect_hints = true
detect_repetitive_words = true
detect_layout_patterns = true
detect_reused_assets = true
detect_duplicates = true
duplicate_flag = "might be a small change - investigate"

[actions]
generate_docx = true
whatsapp_send = true
stop_on_complete = false

[proctor]
validate_after_scan = true
validate_after_extraction = true
```

The agent MUST modify this config on the target machine:
1. Copy from `templates/config.toml` to root
2. Verify `max_disk_gb = 2` is set
3. Adjust platform-specific directories

---

## Phase 4: Git Init

```bash
cd $ROOT
git init
git config user.name "Doc Intelligence Pipeline"
git config user.email "pipeline@localhost"
```

Every scan result, extraction output, and knowledge file is committed. This gives:
- Full history of document changes over time
- Rollback capability
- Branching for experimental extraction rules

---

## Phase 5: Document Collection (Synchronous, Dir-by-Dir)

**CRITICAL**: No async, no parallel scans. The pipeline walks one directory at a time, fully completes it, saves results, then moves to the next.

**Algorithm (in scripts/pipeline.py):**

```
for each scan_directory in config:
    walk the directory tree (os.walk, sync, depth-limited)
    collect all .docx file paths
    append to root/collected/manifest.jsonl
    git add + commit the manifest update
    move to next directory
```

**Manifest format** (root/collected/manifest.jsonl):
```json
{"path": "C:\\Users\\Ahmed\\Downloads\\report.docx", "size_bytes": 245760, "mtime": "2026-07-20T14:30:00", "source_dir": "Downloads", "collected_at": "2026-07-25T06:00:00"}
```

---

## Phase 6: Cron Setup (Daily 06:00)

The cron job scans common directories every day at 06:00 local time.

**Scan targets by platform:**

| Platform | Directories Scanned |
|----------|-------------------|
| Windows  | `%USERPROFILE%\Downloads`, `%USERPROFILE%\Desktop`, `%USERPROFILE%\Documents`, `%USERPROFILE%\OneDrive` |
| macOS    | `~/Downloads`, `~/Desktop`, `~/Documents`, `~/Library/CloudStorage` (iCloud) |
| Linux    | `~/Downloads`, `~/Desktop`, `~/Documents` |

**Scheduler setup by platform:**

- **macOS**: launchd plist at `~/Library/LaunchAgents/com.docintel.scan.plist`
- **Linux**: crontab entry: `0 6 * * * cd $ROOT && python3 scripts/pipeline.py scan`
- **Windows**: `schtasks /create /tn "DocIntelScan" /tr "python C:\DocIntel\scripts\pipeline.py scan" /sc daily /st 06:00`

See `references/cron-setup.md` for exact commands per platform.

---

## Phase 7: Parse & Extract Loop

After collection completes, the pipeline enters the extraction loop:

```
wait 1000ms
for each unprocessed file in manifest:
    parse .docx -> extract:
        - full text (python-docx)
        - paragraph count
        - heading structure (styles)
        - embedded images count
        - tables count
    save extracted text to root/extracted/{file_hash}.txt
    save metadata to root/extracted/{file_hash}.json
    git add + commit
    wait 1000ms between batches of config.extraction.batch_size
```

**Wait rationale**: The 1000ms pause prevents CPU/disk contention and allows the system to remain responsive during large scans.

---

## Phase 8: Knowledge Building

After extraction, the pipeline analyzes all extracted text for patterns. Each pattern type is saved as a "skill" file under `root/knowledge/`.

### 8a: Hints Detection
Scan for imperative language, suggestions, tips:
- Lines starting with "Tip:", "Note:", "Hint:", "Important:"
- Sentences with "should", "must", "recommend", "always", "never"
- **Output**: `root/knowledge/hints.jsonl`

### 8b: Repetitive Words
Find words/phrases appearing across multiple documents:
- TF-IDF across the corpus
- Bigrams/trigrams that repeat across >= 3 documents
- **Output**: `root/knowledge/repetitive_words.jsonl`

### 8c: Layout Patterns
Identify document structure patterns:
- Heading hierarchy (H1 -> H2 -> H3 depth)
- Table density (tables per page)
- List usage (bullet vs numbered ratio)
- Image placement patterns
- **Output**: `root/knowledge/layout_patterns.jsonl`

### 8d: Close Assets Reused
Detect images and embedded objects reused across documents:
- Hash embedded images (MD5 of image bytes)
- Flag images appearing in >= 2 documents
- **Output**: `root/knowledge/reused_assets.jsonl`

### 8e: Duplicates (Soft Flag)
Find near-duplicate documents. **NEVER flag as errors/red** -- flag as "might be a small change, investigate":
- MinHash + LSH for text similarity > 0.85
- File size within 5% of each other
- Same heading structure but different content
- **Output**: `root/knowledge/duplicates.jsonl` with `flag: "soft"` and `message: "might be a small change - investigate"`

---

### Interpreting Knowledge Output

Each JSONL file in `root/knowledge/` follows a specific schema. Here is how to read them:

**hints.jsonl** — actionable tips found in documents:
| Field | Meaning |
|-------|---------|
| `doc_hash` | Which document this came from (cross-reference with `extracted/{hash}.json`) |
| `source_path` | Original file path on disk |
| `pattern` | Which regex triggered (e.g. "should/must/recommend") |
| `match` | The exact matched phrase |
| `snippet` | ~160 chars of surrounding context |

**repetitive_words.jsonl** — recurring terms across the corpus:
| Field | Meaning |
|-------|---------|
| `word` | The term (4+ chars, lowercase) |
| `doc_count` | Number of documents containing this word |
| `total_frequency` | Total occurrences across all documents |

High `doc_count` with high `total_frequency` indicates a domain term.  
High `total_frequency` with low `doc_count` means one document is repeating it heavily.

**layout_patterns.jsonl** — document structure fingerprint:
| Field | Meaning |
|-------|---------|
| `heading_count` | Number of styled headings (Heading 1/2/3) |
| `table_count` | Number of tables |
| `image_count` | Number of embedded images |
| `tables_per_100_paras` | Table density (high = data-heavy doc) |
| `headings_per_100_paras` | Heading density (high = structured/report doc) |

**reused_assets.jsonl** — images shared across documents:
| Field | Meaning |
|-------|---------|
| `image_md5` | MD5 hash of the image bytes |
| `occurrence_count` | How many documents reuse this image |
| `documents` | List of source paths |

An image with `occurrence_count >= 3` is likely a template asset (logo, header graphic).  
An image with `occurrence_count == 2` may indicate document duplication — cross-check with `duplicates.jsonl`.

**duplicates.jsonl** — near-duplicate document pairs (SOFT flag):
| Field | Meaning |
|-------|---------|
| `flag` | Always `"soft"` — never an error |
| `message` | `"might be a small change - investigate"` |
| `similarity` | Jaccard similarity (0.0–1.0) on 3-gram shingles |
| `size_ratio` | Ratio of file sizes (1.0 = identical size) |
| `recommendation` | Human-readable suggestion |

High `similarity` (>0.90) + high `size_ratio` (>0.95) = nearly identical files.  
High `similarity` + low `size_ratio` = one is likely a subset or excerpt.  
Moderate `similarity` (0.85–0.90) = same template, different content — expected for form letters.

---

## Phase 9: Actions

Based on extracted knowledge, the pipeline can trigger actions:

### Action: Generate .docx
Create a summary .docx report:
- List of all collected documents
- Key patterns found
- Duplicate candidates
- Recommended actions

### Action: WhatsApp Send
Send notifications via WhatsApp (requires Hermes gateway WhatsApp configured):
- Daily scan summary
- New documents found
- Duplicate candidates found

### Action: Stop
Graceful pipeline termination. Triggered when:
- All documents processed
- `stop_on_complete = true` in config
- Manual interrupt signal received

---

## Phase 10: Proctor Validation

The proctor validates every pipeline phase:

```
1. Root exists + writable + has >= 2GB free
2. config.toml exists + valid TOML + memory = 2GB
3. Git repo initialized + clean working tree
4. Manifest populated (>= 1 file if scan ran)
5. Extracted files match manifest count
6. Knowledge files are valid JSONL
7. Cron job is scheduled + next run time is valid
8. Dependencies installed (python-docx, tomli, etc.)
```

Run proctor: `python3 scripts/pipeline.py proctor`

---

## Deployment Instructions

When the agent loads this skill on a target machine:

1. **Read the skill**: `skill_view(name='doc-intelligence-pipeline')`
2. **Copy scripts to root**: Use `skill_view(name='doc-intelligence-pipeline', file_path='scripts/install.sh')` to read, then `write_file` to deploy
3. **Run install**: `bash install.sh` (handles OS detection, root creation, config, git, cron)
4. **Run first scan**: `python3 pipeline.py scan`
5. **Run extraction**: `python3 pipeline.py extract`
6. **Run knowledge build**: `python3 pipeline.py knowledge`
7. **Run proctor**: `python3 pipeline.py proctor`
8. **Verify cron**: Check scheduler is active for daily 06:00 runs

## Common Pitfalls

1. **Windows paths with spaces**: Always quote paths containing spaces in schtasks and scripts
2. **macOS permissions**: First run on macOS may trigger "Terminal wants to access Documents" -- user must approve
3. **WSL paths**: WSL sees Windows drives at `/mnt/c/` -- config must use Linux-style paths if running inside WSL
4. **python-docx not installed**: The install script installs it, but on some systems `pip` vs `pip3` matters
5. **Cron not running**: On macOS, launchd may need `launchctl load` after plist creation
6. **Disk space**: The 2GB check is a minimum -- large document corpora may need more
7. **Duplicate flagging is SOFT**: Never present duplicates as errors. Always use the language "might be a small change -- investigate" from config

## Verification Checklist

After deployment, verify:
- [ ] Root directory created at correct platform path
- [ ] `config.toml` exists with `max_disk_gb = 2`
- [ ] `git log` shows at least the initial commit
- [ ] `python3 scripts/pipeline.py proctor` passes all checks
- [ ] Cron job visible: `crontab -l` (Linux), `launchctl list | grep docintel` (macOS), `schtasks /query /tn DocIntelScan` (Windows)
- [ ] Test .docx in scanned directory is picked up on next cron run
- [ ] Knowledge files in `root/knowledge/` are valid JSONL
- [ ] Duplicates flagged with "might be a small change" language, never as errors

## Pipeline Commands Quick Reference

| Command | What it does | Output location |
|---------|-------------|-----------------|
| `python3 scripts/pipeline.py scan` | Walk dirs, collect .docx paths (sync, dir-by-dir) | `collected/manifest.jsonl` |
| `python3 scripts/pipeline.py extract` | Parse .docx files, extract text + metadata (1000ms batch pause) | `extracted/{hash}.txt` + `.json` |
| `python3 scripts/pipeline.py knowledge` | Analyze corpus: hints, words, layout, assets, duplicates | `knowledge/*.jsonl` |
| `python3 scripts/pipeline.py actions` | Generate .docx report, WhatsApp notify, or stop | `actions/summary_{date}.docx` |
| `python3 scripts/pipeline.py proctor` | Validate entire pipeline (8 checks) | stdout (pass/fail per check) |
| `python3 scripts/pipeline.py full` | Run scan -> extract -> knowledge -> actions -> proctor | All of the above |
| `bash scripts/install.sh` | OS detect, root create, config write, git init, deps, cron | `$ROOT/` (everything) |
| `source scripts/env.sh` | Set ROOT, PYTHON, CONFIG_PATH in current shell | Environment variables |

## File Inventory

```
{root}/
├── config.toml                 # Pipeline configuration (2GB memory)
├── .git/                       # Git repository
├── collected/
│   └── manifest.jsonl          # All discovered .docx paths
├── extracted/
│   ├── {hash}.txt              # Extracted full text
│   └── {hash}.json             # Document metadata
├── knowledge/
│   ├── hints.jsonl             # Imperative tips & suggestions
│   ├── repetitive_words.jsonl  # Recurring terms across docs
│   ├── layout_patterns.jsonl   # Document structure patterns
│   ├── reused_assets.jsonl     # Images/objects in >= 2 docs
│   └── duplicates.jsonl        # Near-duplicates (soft-flagged)
├── actions/
│   └── summary_{date}.docx     # Generated summary reports
└── logs/
    └── pipeline.log            # Execution log
```
