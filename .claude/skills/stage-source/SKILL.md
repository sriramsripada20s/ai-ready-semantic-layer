---
name: stage-source
description: Stage a source table (profile-driven, human-approved). Draft stg_<source>__<table>.sql and its tests from real profiling facts, plan first, and write files only after user approval.
argument-hint: <table>
---

# Stage a source table (profile-driven, human-approved)

Draft `stg_<source>__<table>.sql` and its tests from REAL profiling facts, not guesses. The user is building this project to learn: explain every rule, plan first, and never write files until the user approves the plan and answers the open business questions.

## Input

The table name, e.g. `customers` or `order_items`. The source name defaults to `ecom` (check `models/staging/_sources.yml`). If no table is given, ask which one.

Table requested: `$ARGUMENTS`

## Safety rules (always)

- Never read, print or edit `.env` or any `*.p8` file.
- Allowed commands: `dbt show`, `dbt compile`, `dbt ls`. Ask before running anything else. Never run `dbt build`/`dbt run` against prod, never `git commit` or `git push`.
- Windows PowerShell: load env vars first with `. .\scripts\load_env.ps1` if a dbt command fails with a missing env var; use the user's conda env `semantic-layer`.
- Run dbt only from the repo root.

## Step 1: Gather facts

Read the profile rows for the table:

```
dbt show --inline "select column_name, column_kind, data_type, null_pct, distinct_count, repeated_values, untrimmed_count, case_or_space_variants, empty_string_count, numeric_text_count, non_positive_count, future_count, sample_values, suggested_action from {{ ref('source_profile') }} where table_name = '<table>' order by column_position" --limit 100
```

If `source_profile` doesn't exist or is empty, tell the user to run `dbt run --select source_profile` (it scans every column, so it's on demand) and stop.

For low-cardinality text columns, get the exact distinct values with counts so you can see variants (wrap in brackets to reveal spaces):

```
dbt show --inline "select '[' || <col> || ']' as v, count(*) as n from {{ source('<source>', '<table>') }} group by 1 order by 2 desc" --limit 50
```

Read `models/staging/_sources.yml`, `models/staging/_staging.yml`, the `seeds/` folder (lookup tables such as country or code aliases) and any existing staging models, to match conventions. Read `docs/data_quality.md` if it exists.

For key-like columns ending in `_id`, check orphans against the parent source with a `dbt show --inline` left join if the parent is obvious.

## Step 2: Present the plan (do NOT write files yet)

Show one table:

| column | profile finding (with counts) | proposed rule | test that proves it | fix / flag / exclude / expected |

Then list OPEN QUESTIONS: every decision that is a business rule, not a mechanical fix. Typical ones:

- Is this value a synonym or a different category? (e.g. 'complete' vs 'completed')
- Is a pattern a test/dummy record? (e.g. emails at a test domain)
- Is a future date a bug or a scheduled event? (e.g. future deleted_at)
- Are NULLs expected here (optional field) or a defect?
- Should a bad row be flagged, excluded in staging, or excluded later in marts?
- Which duplicate wins (latest load vs first)?

State your recommendation for each question, but WAIT for the user's answers.

## Step 3: Write the files (after approval)

`models/staging/stg_<source>__<table>.sql` conventions:

- CTEs: source -> optional deduplicated -> cleaned -> final select.
- Clean, don't transform: rename, cast, trim, standardize casing, map synonyms, deduplicate, parse text-to-number (`try_cast(replace(replace(col,'$',''),',','') as decimal(...))`).
- No joins except small lookup seeds via `ref()`.
- FLAG questionable rows with booleans (`is_valid_*`, `is_test_*`, `is_deleted`); don't delete them in staging unless the user decided a row is not data at all (e.g. zero/negative quantity lines).
- Empty strings -> NULL with `nullif(trim(col), '')`.
- Deduplicate with `qualify row_number() over (partition by <key> order by <load col> desc) = 1`.
- Use cross-database macros where dialects differ, e.g. `{{ dbt.dateadd(...) }}`.
- Explicit casts for dates, timestamps and money.
- Every rule gets a comment naming the profile finding it fixes.
- Rules that depend on PII must still work when the column is masked (e.g. detect test accounts by email domain, which a mask like `*****@domain` preserves).

`models/staging/_staging.yml` (append; don't rewrite other models' entries):

- Model description summarizing the cleaning.
- `unique` + `not_null` on the primary key (severity error: proves the dedupe).
- `accepted_values` for categoricals, using the CLEANED values.
- `relationships` to seeds or parent models where a lookup exists.
- `dbt_utils.accepted_range` / `dbt_utils.expression_is_true` for ranges and date rules.
- `severity: warn` for issues that are flagged but shouldn't block the build (e.g. invalid emails, late-arriving foreign keys), with a comment explaining why.
- PII columns: add `meta: {pii: true}`.

If a mapping needs a new seed (e.g. code aliases), propose the CSV contents first.

## Step 4: Hand over

- Show a short summary of what was created and why.
- Give the user the commands to run themselves:

  ```
  dbt seed            # only if a seed was added or changed
  dbt build --select +stg_<source>__<table>
  ```

- Tell them which tests should pass, which should WARN (and the expected counts from the profile), so they can verify the result.
- Offer the rows to add to `docs/data_quality.md`: issue | cause | before (count) | fix | after | test.
- Suggest the commit message: `feat(staging): <table> cleaned and tested`. Do not commit.

## If the build fails

Read the error, explain the cause in plain words, propose the smallest fix, and wait for approval before editing.
