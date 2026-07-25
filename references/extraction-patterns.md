# Extraction Patterns — Deep Dive

How `pipeline.py knowledge` detects each of the 5 pattern types. This reference
documents the algorithms, tuning knobs, and edge cases.

---

## 1. Hints Detection

### Algorithm
Regex-based scanning of full document text for imperative and advisory language.

### Patterns Used

| Pattern | Regex | What it catches |
|---------|-------|----------------|
| Label prefixes | `(?i)\b(tip|note|hint|important|warning|caution)\s*[:;—-]` | "Tip: always save first", "NOTE — do not edit" |
| Modal verbs | `(?i)\b(should|must|recommend|always|never|ensure|avoid)\b` | "You should back up", "must be completed" |
| Stock phrases | `(?i)\b(best practice|pro tip|key takeaway|remember that)\b` | "Best practice: use version control" |

### Output Schema
```json
{"doc_hash": "a1b2c3d4", "source_path": "/Users/…/guide.docx", "pattern": "(?i)\\b(should|must|…)\\b", "match": "should", "snippet": "…you should always validate input before processing…"}
```

### Tuning
- `knowledge.detect_hints` in config.toml toggles this on/off
- Add custom patterns by editing the `hint_patterns` list in `pipeline.py`
- Snippet window: 40 chars before match, 120 chars after

### False Positives
- "Should" in legal documents (not a hint, just obligation)
- "Must" in requirements docs (not a tip, a requirement)
- Reduce noise by excluding documents with >50 matches (likely a specification, not hints)

---

## 2. Repetitive Words

### Algorithm
Simple term frequency with cross-document counting. Not full TF-IDF (avoiding
scipy/numpy dependency for portability).

1. Tokenize each document: `re.findall(r"\b[a-zA-Z]{4,}\b", text.lower())`
2. Count per-document frequencies
3. Count document presence (in how many docs does each word appear?)
4. Filter: `doc_count >= 3 AND total_frequency >= doc_count * 3`

### Output Schema
```json
{"word": "authentication", "doc_count": 5, "total_frequency": 47}
```

### Interpreting
- High `doc_count` + high `total_frequency` = domain term or project jargon
- High `total_frequency` + low `doc_count` = one document is very repetitive
- Add discovered terms to project glossary

### Limitations
- English-only word boundary (`[a-zA-Z]`). Arabic, CJK, Cyrillic not captured.
- No stopword removal (add common words to exclusion list if needed)
- 4-char minimum (avoids noise from "the", "and", "for")

---

## 3. Layout Patterns

### Algorithm
Structural metadata extraction from python-docx:

1. Count paragraphs with "Heading" in style name → heading_count
2. Count `doc.tables` → table_count
3. Count relationships with "image" reltype → image_count
4. Count all paragraphs → paragraph_count
5. Derive ratios: tables_per_100_paras, headings_per_100_paras

### Output Schema
```json
{"doc_hash": "a1b2c3d4", "source_path": "…", "heading_count": 12, "paragraph_count": 145, "table_count": 3, "image_count": 7, "char_count": 28450, "word_count": 4120, "tables_per_100_paras": 2.1, "headings_per_100_paras": 8.3}
```

### Interpreting
- `headings_per_100_paras > 10` = heavily structured (report, manual, legal doc)
- `headings_per_100_paras < 2`  = prose-heavy (essay, article, letter)
- `tables_per_100_paras > 5`   = data-heavy (spreadsheet export, financial report)
- `image_count > paragraph_count / 10` = image-heavy (presentation, catalog)

---

## 4. Reused Assets (Images)

### Algorithm
1. Open .docx as ZIP archive
2. List all files in `word/media/`
3. Read each image, compute MD5 hash
4. Group by hash, flag groups with `len(group) >= 2`

### Output Schema
```json
{"image_md5": "d41d8cd98f00b204e9800998ecf8427e", "occurrence_count": 3, "documents": ["/Users/…/report1.docx", "/Users/…/report2.docx", "/Users/…/proposal.docx"]}
```

### Security
- Hashes are MD5 (fast, collision-resistant enough for image dedup)
- Image bytes are NOT saved — only the hash and source paths
- No image content leaves the machine

---

## 5. Duplicate Detection (Soft Flag)

### Algorithm — MinHash Approximation via Jaccard on 3-gram Shingles

1. **Shingling**: Split text into word 3-grams
   ```
   "the quick brown fox" → {"the quick brown", "quick brown fox"}
   ```
2. **Jaccard similarity**: `|A ∩ B| / |A ∪ B|`
3. **Size check**: Compare file sizes, flag if within 5%
4. **Threshold**: Similarity > 0.85 OR (similarity > 0.70 AND size_ratio > 0.95)

### Output Schema
```json
{"flag": "soft", "message": "might be a small change - investigate", "doc_a": "/Users/…/v1.docx", "doc_b": "/Users/…/v2.docx", "similarity": 0.9234, "size_ratio": 0.9876, "recommendation": "Review for potential merge or differentiation."}
```

### Why Not Real MinHash + LSH?
Full MinHash with Locality-Sensitive Hashing requires `datasketch` or similar
libraries. This skill uses a direct Jaccard comparison which is:
- Zero dependencies beyond stdlib
- Accurate enough for <1000 documents
- Slower for large corpora (O(n²) pairwise comparisons)

For >1000 documents, install `datasketch` and uncomment the MinHash path in
`pipeline.py`.

### Flagging Policy (HARD RULE)
- `flag` is ALWAYS `"soft"`
- `message` ALWAYS contains "investigate" or "might be"
- NEVER use words like "error", "duplicate", "problem", "conflict", "warning"
- The pipeline NEVER deletes, moves, or modifies source documents
- Human review is always required before any merge/delete action
