# welcometothedisco

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

---

## Backfill: `pairs` collection (Bradley–Terry ranking prep)

### Prerequisites

```bash
pip install google-cloud-firestore --break-system-packages
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/jukebox-996de-service-account.json
```

### 1. Back up Firestore first

```bash
gcloud firestore export gs://<your-bucket>/backup-before-pairs \
  --project=jukebox-996de
```

### 2. Dry run (safe — writes nothing to Firestore)

```bash
python3 backfill_pairs.py
```

Reads all polls and rankings, computes every `pairs` and `voters` doc, runs
validation, prints a summary, and writes the full output to `backfill_preview.json`.
Review that file before committing.

### 3. Commit

```bash
python3 backfill_pairs.py --commit
```

Writes:
- `pair_key` field onto every poll doc (update, no other fields touched)
- `pairs/{pairKey}` docs (set/overwrite)
- `pairs/{pairKey}/voters/{voterId}` docs (set/overwrite)

### Re-running is safe

All writes use `set()` (overwrite) for pair/voter docs and field `update` for polls.
Running the script twice produces identical results — no duplicates, no data loss.

### Testing (no Firestore required)

```bash
python3 -m pytest test_backfill_pairs.py -v
# or
python3 test_backfill_pairs.py
```

### Limit flag (for testing against production data)

```bash
python3 backfill_pairs.py --limit 10
```

Processes only the first 10 polls (dry run unless `--commit` is also passed).
