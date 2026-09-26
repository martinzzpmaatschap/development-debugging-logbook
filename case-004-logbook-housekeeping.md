# Case #004: Logbook Housekeeping — Missing Index Entries, a Broken Link, Lost Markdown

> **TL;DR:** The logbook itself had three quiet defects: the README indexed only 1 of 4 existing write-ups, a link in Case #003 pointed to a file that was committed as `trust_prompts (1).yml` (browser duplicate-download suffix), and the 2025-09-30 debug log had lost all markdown formatting on the way into the repo. None of them produced an error — they only showed up when reading the repo as a reader would. Fixed by renaming the files, indexing every case in the README, and restoring headings, code fences, a real table and a checklist.

## Environment

| Component | Detail |
|-----------|--------|
| Repo | `development-debugging-logbook` (Markdown only, hosted on GitHub) |
| Affected files | `README.md`, `case-003-espanso-detection-failure.md`, `trust_prompts (1).yml`, `Case Study #002_ De RLS-Vesting - Architectuurconflicten.md`, `2025-09-30-supabase-user-deletion-foreign-keys.md` |
| Detected on | 26 September 2026 (date verified with `TZ="Europe/Amsterdam" date`) |

## Findings

| # | Symptom | Cause | Evidence |
|---|---------|-------|----------|
| 1 | README listed only Case #001 | Files were added in separate commits (`f26b290`, `8df497e`, `821509c`) and the README was never updated alongside them | `README.md` had one entry plus "*More case studies will be added*" |
| 2 | Link `./trust_prompts.yml` in Case #003 led nowhere | The file was committed as `trust_prompts (1).yml` — the ` (1)` is what a browser appends to a second download of the same name | `git ls-tree` on `96f2618^` showed `trust_prompts (1).yml`; `case-003-…md:200` linked `trust_prompts.yml` |
| 2b | Case #002 filename was link-hostile | `Case Study #002_ De RLS-Vesting - ….md` contains spaces and `#`, which URLs read as a fragment separator | Filename in `git ls-tree` on `96f2618^` |
| 3 | 2025-09-30 debug log rendered as one wall of text | Front matter survived, but the body was flat text: no `#` headings, SQL blocks without fences and with the language name glued to the first line (`sqlSELECT`), the constraints table collapsed into a single line, checklist bullets stripped | `2025-09-30-supabase-user-deletion-foreign-keys.md` lines 24, 48, 120, 130–136 before the fix |

The most likely origin of #3 is copy-paste of rendered or plain text instead of the raw Markdown source. That is a probable explanation, not a proven one — the git history only shows the finished file.

## Fixes

### 1. Filenames (commit `96f2618`)

Renamed, content unchanged (git reports both as `R100`, a 100% identical rename):

- `trust_prompts (1).yml` → `trust_prompts.yml`
- `Case Study #002_ De RLS-Vesting - Architectuurconflicten.md` → `case-002-rls-vesting-architectuurconflicten.md`

After the rename the existing link in Case #003 resolves without any edit to the case itself.

### 2. README index

`README.md` now lists all five write-ups — Case #001, the 2025-09-30 debug log, Case #002, Case #003 and this case — each with a short summary and a relative link.

### 3. Restoring the debug log

Formatting only, no change to the technical content:

- `##` / `###` headings for every section and step
- All SQL wrapped in ` ```sql ` fences with the stray `sql` prefix removed; the error output in plain fences
- The collapsed constraints line rebuilt as a five-column Markdown table
- "Why This Happens" as a bullet list, "Prevention Checklist" as a `- [ ]` task list
- Date / Issue / Stack turned into a list; the plain-text title line that duplicated the `#` heading was dropped

## Verification

```bash
# every relative link in README and the cases must point to an existing file
grep -ohE '\]\(\./[^)]+\)' README.md case-*.md | sed 's/^](//; s/)$//' | sort -u | while read -r f; do
  test -e "$f" && echo "OK   $f" || echo "MISS $f"
done
```

Result: every target reports `OK`, none `MISS`. The debug log was additionally compared word-for-word with the original after stripping Markdown syntax: the only differences are the dropped duplicate title line and the table, whose characters are identical once whitespace is ignored.

## Lessons Learned

### 1. Rename downloads the moment they arrive
` (1)`, spaces, `#` and `:` in a filename are all invisible in the browser and all harmful in a repo. Use a fixed pattern — `{project}-{what}-{YYYY-MM-DD}.ext` — before the file goes near `git add`.

### 2. A new file is not done until it is in the index
Adding a case and adding its README entry belong in the same commit. Three cases were "published" without being discoverable.

### 3. Run a link check before every push
A dead relative link produces no error anywhere. The `grep`/`test -e` loop above takes a second and would have caught finding #2 immediately.

### 4. Pasting text is not pasting Markdown
When content moves between chat, editor and repo, the rendered result is what gets copied, not the source. After committing, open the file on GitHub and look at it as a reader.

### 5. "Facts, no assumptions" applies to documentation too
Every one of these defects looked fine in the file list. Only opening the README, following the links and reading the rendered page showed the problem.

## Open Point

`case-001-auth-trigger/report.md` shows the same symptom — flat text without Markdown headings or fences. It was outside the scope of this repair and is left as a follow-up.

## Files

- [`README.md`](./README.md) — index with all five entries
- [`2025-09-30-supabase-user-deletion-foreign-keys.md`](./2025-09-30-supabase-user-deletion-foreign-keys.md) — restored debug log
- [`case-002-rls-vesting-architectuurconflicten.md`](./case-002-rls-vesting-architectuurconflicten.md) — renamed
- [`trust_prompts.yml`](./trust_prompts.yml) — renamed

---

**Status:** ✅ Resolved
**Date:** 26 September 2026
**Outcome:** Every case is indexed, every link resolves, and the debug log renders as intended
