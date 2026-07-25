# Duplicate Detection — Algorithm & Tuning

How `pipeline.py knowledge` identifies near-duplicate .docx files without
flagging them as errors. Everything here is configurable in `config.toml`.

---

## Algorithm Overview

```
Document A text ──► 3-gram shingles ──► set A
Document B text ──► 3-gram shingles ──► set B

Jaccard(A, B) = |A ∩ B| / |A ∪ B|

If Jaccard > 0.85  ──►  SOFT FLAG  "might be a small change — investigate"
If Jaccard > 0.70 AND file sizes within 5% ──►  SOFT FLAG
```

## Why 3-gram Shingles?

Word 3-grams capture phrase-level similarity without requiring full semantic
analysis:

```
"the customer requested a refund for the defective product"
→ {"the customer requested", "customer requested a", "requested a refund",
   "a refund for", "refund for the", "for the defective", "the defective product"}
```

- **1-grams** (single words): too noisy — "the", "a", "and" dominate
- **2-grams**: decent but misses longer phrase matches
- **3-grams**: sweet spot — catches "requested a refund" style phrases
- **5-grams**: too strict — minor word changes break matches

## Tuning Knobs (config.toml)

```toml
[knowledge]
similarity_threshold = 0.85    # Primary threshold (Jaccard >= this → flag)
duplicate_flag = "might be a small change - investigate"  # Message text
min_corpus_size = 3            # Don't run analysis with <3 documents
```

### Choosing the Threshold

| Threshold | What it catches | False positive risk |
|-----------|----------------|-------------------|
| 0.95 | Near-identical copies (save-as with minor edits) | Very low |
| 0.90 | Same template, slightly different content | Low |
| **0.85** (default) | Same template, different data filled in | Moderate |
| 0.80 | Same topic, different document structure | High |
| 0.70 | Same general subject area | Very high |

### Size Ratio Check

Even when Jaccard is moderate (0.70–0.85), if two files have nearly identical
sizes (within 5%), they're likely variants:

```python
size_ratio = min(size_a, size_b) / max(size_a, size_b)
if similarity > 0.70 and size_ratio > 0.95:
    flag_as_soft_duplicate()
```

## What the Output Looks Like

```json
{
  "flag": "soft",
  "message": "might be a small change - investigate",
  "doc_a": "C:\\Users\\Ahmed\\Documents\\invoice_template_v1.docx",
  "doc_b": "C:\\Users\\Ahmed\\Documents\\invoice_template_v2.docx",
  "similarity": 0.9234,
  "size_ratio": 0.9876,
  "recommendation": "Review for potential merge or differentiation."
}
```

## What This Is NOT

- **NOT a file deduplicator** — never deletes, moves, or modifies files
- **NOT an error detector** — similarities are information, not problems
- **NOT a copyright checker** — does not compare against external sources
- **NOT a plagiarism tool** — only compares documents already in the pipeline

## When Similarity Is Expected

Some document types naturally have high similarity without being "duplicates":

- **Form letters**: Same template, different recipient → Jaccard 0.85–0.95
- **Invoices**: Same layout, different amounts → Jaccard 0.80–0.90
- **Weekly reports**: Same structure, different data → Jaccard 0.75–0.88
- **Contracts**: Same clauses, different parties → Jaccard 0.70–0.85

The pipeline flags ALL of these — that's intentional. The human reviewer decides
which are "real" duplicates and which are expected template reuse.

## Scaling

The current implementation does O(n²) pairwise comparisons. Performance guide:

| Documents | Comparisons | Approximate time |
|-----------|------------|-----------------|
| 10 | 45 | <1 second |
| 50 | 1,225 | ~2 seconds |
| 100 | 4,950 | ~10 seconds |
| 500 | 124,750 | ~4 minutes |
| 1000 | 499,500 | ~15 minutes |

For >1000 documents, install `datasketch` (`pip install datasketch`) and
switch to the MinHash+LSH path. This reduces to O(n) with configurable
false-positive/negative trade-offs.
