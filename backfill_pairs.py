#!/usr/bin/env python3
"""
backfill_pairs.py — One-time Firestore backfill for the `pairs` collection.

Supports two poll formats:
  ARTIST — detected by `artist1ID` field; track_details is a MAP
  ALBUM  — detected by `album1_id` field (snake_case); track_details is a LIST

Usage:
  python3 backfill_pairs.py              # dry run: writes backfill_preview.json
  python3 backfill_pairs.py --commit     # write to Firestore
  python3 backfill_pairs.py --limit 20  # process only first 20 polls (testing)

Re-running is safe: pair/voter docs are overwritten with set(), poll updates are
idempotent field additions.
"""

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone

import google.cloud.firestore as firestore

# ─── Config ───────────────────────────────────────────────────────────────────
DEFAULT_KEY = "/home/gift/Downloads/mycassette/servicekey/jukebox-996de-firebase-adminsdk-9n2km-3f149867fb.json"
PROJECT_ID = "jukebox-996de"
MIN_ROUNDS = 1      # voter must have >= MIN_ROUNDS total to be "counted"
INCLUDE_BONUS = False  # whether to count isBonus rounds toward rankings

# Worked-check poll for diagnostics
_WORKED_CHECK_VERSUS = "i0OBlCaF5TPamPoBCP1Y"
_WORKED_CHECK_VOTER  = "5I4TCyfmEySXWQMbGGxey7FUVm53"


# ─── Pure aggregation helpers ─────────────────────────────────────────────────

def make_pair_key(id1: str, id2: str) -> str:
    a, b = sorted([id1, id2])
    return f"{a}_{b}"


def map_rounds_to_ab(id1: str, side1_rounds: int, id2: str, side2_rounds: int) -> tuple:
    """
    Return (rounds_a, rounds_b) where a is the lex-lower ID.
    side1_rounds / side2_rounds are already mapped to id1 / id2 respectively.
    """
    if id1 < id2:
        return side1_rounds, side2_rounds
    else:
        return side2_rounds, side1_rounds


def detect_format(d: dict):
    """Return 'album', 'artist', or None."""
    if d.get("album1_id"):   # snake_case → new album format
        return "album"
    if d.get("artist1ID"):   # camelCase → classic artist format
        return "artist"
    return None


def compute_rounds_from_track_details(track_details, poll_format: str,
                                      diag: dict) -> tuple:
    """
    Compute (side1, side2, bonus1, bonus2) from track_details.
    side1/side2 = non-bonus rounds; bonus1/bonus2 = bonus rounds.
    side1 is artist1/album1 side; side2 is artist2/album2 side (not yet a/b).
    Unusual winner values are collected in diag['winner_values'].
    """
    side1, side2, bonus1, bonus2 = 0, 0, 0, 0
    if not track_details:
        return side1, side2, bonus1, bonus2

    if poll_format == "artist":
        if not isinstance(track_details, dict):
            return side1, side2, bonus1, bonus2
        for rnd in track_details.values():
            if not isinstance(rnd, dict):
                continue
            is_bonus = bool(rnd.get("isBonus", False))
            winner = rnd.get("Winner") or ""
            a1id = rnd.get("artist1trackID") or ""
            a2id = rnd.get("artist2trackID") or ""

            # Collect unusual winner values (not empty, not a normal track match)
            if not winner:
                diag["winner_values"].add("artist:EMPTY")
            elif winner != a1id and winner != a2id:
                diag["winner_values"].add(f"artist:OTHER:{winner[:20]}")

            if winner and a1id and winner == a1id:
                if is_bonus: bonus1 += 1
                else:        side1  += 1
            elif winner and a2id and winner == a2id:
                if is_bonus: bonus2 += 1
                else:        side2  += 1

    elif poll_format == "album":
        rounds = track_details if isinstance(track_details, list) \
                 else list(track_details.values()) if isinstance(track_details, dict) \
                 else []
        for rnd in rounds:
            if not isinstance(rnd, dict):
                continue
            is_bonus = bool(rnd.get("isBonus", False))
            winner = rnd.get("winner") or ""

            if winner not in ("Album1", "Album2"):
                diag["winner_values"].add(f"album:{winner!r}")

            if winner == "Album1":
                if is_bonus: bonus1 += 1
                else:        side1  += 1
            elif winner == "Album2":
                if is_bonus: bonus2 += 1
                else:        side2  += 1

    return side1, side2, bonus1, bonus2


def compute_voter_shares(rounds_a: int, rounds_b: int) -> tuple:
    total = rounds_a + rounds_b
    if total >= MIN_ROUNDS:
        return rounds_a / total, rounds_b / total, True
    return 0.0, 0.0, False


def pool_voter_polls(polls: dict) -> dict:
    total_a = sum(p["rounds_a"] for p in polls.values())
    total_b = sum(p["rounds_b"] for p in polls.values())
    share_a, share_b, counted = compute_voter_shares(total_a, total_b)
    voted_ats = [p["voted_at"] for p in polls.values() if p["voted_at"] is not None]
    return {
        "rounds_a": total_a,
        "rounds_b": total_b,
        "share_a":  share_a,
        "share_b":  share_b,
        "counted":  counted,
        "updated_at": max(voted_ats) if voted_ats else None,
        "polls": polls,
    }


def validate_pair(pair_key: str, pair_doc: dict, voter_docs: dict) -> list:
    errors = []
    votes_a, votes_b = pair_doc["votes_a"], pair_doc["votes_b"]
    voter_count       = pair_doc["voter_count"]
    rounds_a, rounds_b = pair_doc["rounds_a"], pair_doc["rounds_b"]
    versus            = pair_doc["versus"]

    if abs((votes_a + votes_b) - voter_count) >= 1e-9:
        errors.append(
            f"{pair_key}: votes_a+votes_b={votes_a+votes_b:.9f} != voter_count={voter_count}"
        )

    vra = sum(v["rounds_a"] for v in voter_docs.values())
    vrb = sum(v["rounds_b"] for v in voter_docs.values())
    if rounds_a != vra:
        errors.append(f"{pair_key}: pair.rounds_a={rounds_a} != voter sum={vra}")
    if rounds_b != vrb:
        errors.append(f"{pair_key}: pair.rounds_b={rounds_b} != voter sum={vrb}")

    vsra = sum(v["rounds_a"] for v in versus.values())
    vsrb = sum(v["rounds_b"] for v in versus.values())
    if rounds_a != vsra:
        errors.append(f"{pair_key}: pair.rounds_a={rounds_a} != versus sum={vsra}")
    if rounds_b != vsrb:
        errors.append(f"{pair_key}: pair.rounds_b={rounds_b} != versus sum={vsrb}")

    total_voter_polls = sum(len(v["polls"]) for v in voter_docs.values())
    total_vs_polls    = sum(v["poll_count"] for v in versus.values())
    if total_voter_polls != total_vs_polls:
        errors.append(
            f"{pair_key}: voter polls={total_voter_polls} != versus poll_count={total_vs_polls}"
        )

    if pair_doc["versus_count"] != len(versus):
        errors.append(
            f"{pair_key}: versus_count={pair_doc['versus_count']} != len(versus)={len(versus)}"
        )

    for voter_id, vdoc in voter_docs.items():
        if vdoc["counted"]:
            sa, sb = vdoc["share_a"], vdoc["share_b"]
            if abs(sa + sb - 1.0) >= 1e-9:
                errors.append(f"{pair_key}/voters/{voter_id}: share_a+share_b={sa+sb:.9f}!=1")
        else:
            if vdoc["share_a"] != 0.0 or vdoc["share_b"] != 0.0:
                errors.append(f"{pair_key}/voters/{voter_id}: uncounted but shares!=0")
        p_ra = sum(p["rounds_a"] for p in vdoc["polls"].values())
        p_rb = sum(p["rounds_b"] for p in vdoc["polls"].values())
        if vdoc["rounds_a"] != p_ra:
            errors.append(f"{pair_key}/voters/{voter_id}: voter.rounds_a={vdoc['rounds_a']}!=poll sum={p_ra}")
        if vdoc["rounds_b"] != p_rb:
            errors.append(f"{pair_key}/voters/{voter_id}: voter.rounds_b={vdoc['rounds_b']}!=poll sum={p_rb}")

    return errors


# ─── I/O helpers ─────────────────────────────────────────────────────────────

def _make_vs_entry():
    return {"rounds_a": 0, "rounds_b": 0, "poll_count": 0, "last_voted_at": None}


def load_rankings(db) -> tuple:
    rankings, image_fallback = {}, {}
    for doc in db.collection("rankings").stream():
        d = doc.to_dict()
        entity_id = d.get("entity_id") or doc.id
        rankings[entity_id] = d
        for opp_id, opp in (d.get("opponents") or {}).items():
            img = (opp or {}).get("opponent_image", "")
            if img and opp_id not in image_fallback:
                image_fallback[opp_id] = img
    return rankings, image_fallback


def resolve_entity_info(entity_id: str, rankings: dict, image_fallback: dict,
                        poll_name_fallback: str = "") -> dict:
    rdoc = rankings.get(entity_id, {})
    name  = rdoc.get("entity_name") or poll_name_fallback or ""
    image = rdoc.get("entity_image") or image_fallback.get(entity_id) or ""
    return {"entity_id": entity_id, "entity_name": name, "entity_image": image}


def build_in_memory(polls_iter, all_poll_ids: set) -> tuple:
    """
    Stream polls and build raw in-memory structures.

    Returns:
      voter_polls:    {(pair_key, voter_id) -> {poll_doc_id -> {versus_id, rounds_a, rounds_b, voted_at}}}
      versus_data:    {pair_key -> {versus_id -> {rounds_a, rounds_b, poll_count, last_voted_at}}}
      pair_names:     {pair_key -> {a_id, b_id, a_name, b_name, entity_type_from_format}}
      poll_pair_keys: {poll_doc_id -> pair_key}
      versus_to_pair: {versus_id -> pair_key}   (authoritative, from actual polls)
      stats:          summary counters
      diag:           diagnostic data for printing
    """
    voter_polls    = defaultdict(dict)
    versus_data    = defaultdict(lambda: defaultdict(_make_vs_entry))
    pair_names     = {}
    poll_pair_keys = {}
    versus_to_pair = {}   # "versus in only one pair" tracking

    stats = {
        "read": 0, "skipped": 0,
        "skip_reasons": defaultdict(int),
        "tagged": 0,
        "format_counts": defaultdict(int),
        "zero_stored_polls": 0,
    }
    diag = {
        "winner_values": set(),
        "comp_with_bonus":  {"match": 0, "mismatch": 0, "examples": []},
        "comp_no_bonus":    {"match": 0, "mismatch": 0, "examples": []},
        "prev_zero_vote":   [],   # polls where stored1+stored2==0
        "worked_check":     None, # set when the specific poll is found
    }

    def skip(reason):
        stats["skipped"] += 1
        stats["skip_reasons"][reason] += 1

    for doc in polls_iter:
        stats["read"] += 1
        d = doc.to_dict()
        poll_id = doc.id
        all_poll_ids.add(poll_id)

        # ── Format detection ──────────────────────────────────────────────────
        fmt = detect_format(d)
        if fmt is None:
            skip("unknown format (no artist1ID or album1_id)"); continue

        voter_id  = d.get("voter_id")
        versus_id = d.get("versus_id")
        if not voter_id:
            skip("missing voter_id"); continue
        if not versus_id:
            skip("missing versus_id"); continue

        # ── Format-specific field mapping ─────────────────────────────────────
        if fmt == "artist":
            id1, id2   = d.get("artist1ID", ""), d.get("artist2ID", "")
            name1, name2 = d.get("artist1Name", "") or "", d.get("artist2Name", "") or ""
            stored1    = d.get("artist1Vote") or 0
            stored2    = d.get("artist2Vote") or 0
        else:  # album
            id1, id2   = d.get("album1_id", ""), d.get("album2_id", "")
            name1, name2 = d.get("album1_name", "") or "", d.get("album2_name", "") or ""
            summary    = d.get("summary") or {}
            stored1    = summary.get("album1_votes") or 0
            stored2    = summary.get("album2_votes") or 0

        if not id1:
            skip(f"missing id1 ({fmt} format)"); continue
        if not id2:
            skip(f"missing id2 ({fmt} format)"); continue
        if id1 == id2:
            skip("id1 == id2"); continue

        stats["format_counts"][fmt] += 1

        # ── Compute rounds from track_details ─────────────────────────────────
        track_details = d.get("track_details")
        s1, s2, b1, b2 = compute_rounds_from_track_details(track_details, fmt, diag)

        # Active rounds depend on INCLUDE_BONUS flag
        active1 = s1 + (b1 if INCLUDE_BONUS else 0)
        active2 = s2 + (b2 if INCLUDE_BONUS else 0)

        # ── Comparison diagnostics ────────────────────────────────────────────
        td_len = (len(track_details) if isinstance(track_details, (list, dict))
                  else 0 if track_details is None else 1)
        comp_key = f"{poll_id} ({fmt})"

        # With bonus
        wb1, wb2 = s1 + b1, s2 + b2
        if wb1 == stored1 and wb2 == stored2:
            diag["comp_with_bonus"]["match"] += 1
        else:
            diag["comp_with_bonus"]["mismatch"] += 1
            if len(diag["comp_with_bonus"]["examples"]) < 10:
                diag["comp_with_bonus"]["examples"].append(
                    f"  {comp_key}: computed=({wb1},{wb2}) stored=({stored1},{stored2})"
                )

        # Without bonus
        if s1 == stored1 and s2 == stored2:
            diag["comp_no_bonus"]["match"] += 1
        else:
            diag["comp_no_bonus"]["mismatch"] += 1
            if len(diag["comp_no_bonus"]["examples"]) < 10:
                diag["comp_no_bonus"]["examples"].append(
                    f"  {comp_key}: computed=({s1},{s2}) stored=({stored1},{stored2})"
                )

        # Previously zero-vote polls (stored totals = 0)
        if stored1 == 0 and stored2 == 0:
            stats["zero_stored_polls"] += 1
            comp_pct = d.get("completion_percentage")
            diag["prev_zero_vote"].append({
                "poll_id": poll_id, "fmt": fmt,
                "comp_s1": s1, "comp_s2": s2,
                "comp_b1": b1, "comp_b2": b2,
                "completion_pct": comp_pct,
                "td_len": td_len,
            })

        # ── Worked check ─────────────────────────────────────────────────────
        if versus_id == _WORKED_CHECK_VERSUS and voter_id == _WORKED_CHECK_VOTER:
            ra, rb = map_rounds_to_ab(id1, active1, id2, active2)
            ra_no_bonus, rb_no_bonus = map_rounds_to_ab(id1, s1, id2, s2)
            pair_key_wc = make_pair_key(id1, id2)
            a_id_wc = min(id1, id2)
            b_id_wc = max(id1, id2)
            diag["worked_check"] = diag.get("worked_check") or []
            diag["worked_check"].append({
                "poll_id": poll_id,
                "id1": id1, "id2": id2,
                "a_id": a_id_wc, "b_id": b_id_wc,
                "pair_key": pair_key_wc,
                "computed_s1_nobonus": s1, "computed_s2_nobonus": s2,
                "computed_b1": b1, "computed_b2": b2,
                "rounds_a_nobonus": ra_no_bonus, "rounds_b_nobonus": rb_no_bonus,
                "rounds_a_active": ra, "rounds_b_active": rb,
                "stored1": stored1, "stored2": stored2,
                "td_len": td_len,
            })

        # ── Pair/versus accumulation ──────────────────────────────────────────
        voted_at = d.get("timestamp")
        pair_key = make_pair_key(id1, id2)
        a_id, b_id = sorted([id1, id2])
        rounds_a, rounds_b = map_rounds_to_ab(id1, active1, id2, active2)

        # Track versus → pair (authoritative from poll data)
        if versus_id not in versus_to_pair:
            versus_to_pair[versus_id] = pair_key
        elif versus_to_pair[versus_id] != pair_key:
            print(f"  [WARN] versus {versus_id} appears in multiple pairs: "
                  f"{versus_to_pair[versus_id]} AND {pair_key} — keeping first")

        poll_pair_keys[poll_id] = pair_key
        stats["tagged"] += 1

        voter_polls[(pair_key, voter_id)][poll_id] = {
            "versus_id": versus_id,
            "rounds_a":  rounds_a,
            "rounds_b":  rounds_b,
            "voted_at":  voted_at,
        }

        vs = versus_data[pair_key][versus_id]
        vs["rounds_a"]     += rounds_a
        vs["rounds_b"]     += rounds_b
        vs["poll_count"]   += 1
        if voted_at is not None:
            if vs["last_voted_at"] is None or voted_at > vs["last_voted_at"]:
                vs["last_voted_at"] = voted_at

        if pair_key not in pair_names:
            pair_names[pair_key] = {
                "a_id": a_id, "b_id": b_id,
                "a_name": "", "b_name": "",
                "entity_type_from_format": fmt,
            }
        pn = pair_names[pair_key]
        # Fill in poll-sourced name fallbacks
        if id1 == a_id:
            if not pn["a_name"]: pn["a_name"] = name1
            if not pn["b_name"]: pn["b_name"] = name2
        else:
            if not pn["a_name"]: pn["a_name"] = name2
            if not pn["b_name"]: pn["b_name"] = name1

    return voter_polls, versus_data, pair_names, poll_pair_keys, versus_to_pair, stats, diag


def seed_from_rankings(versus_data: dict, pair_names: dict,
                       pair_last_played: dict,
                       rankings: dict,
                       versus_to_pair: dict):
    """
    For every opponent+versus in every rankings doc, ensure the pair and versus ID
    exist in versus_data — but only if that versus_id isn't already assigned to a
    DIFFERENT pair from actual poll data ('versus in only one pair' invariant).

    Also collects `played_at` timestamps per pair into `pair_last_played` so empty
    pairs can have a meaningful `created_at`.
    """
    # Start from poll-authoritative assignments; new keys will be added as we seed
    versus_assigned = dict(versus_to_pair)

    for entity_id, rdoc in rankings.items():
        for opp_id, opp_data in (rdoc.get("opponents") or {}).items():
            if entity_id == opp_id:
                continue
            pair_key = make_pair_key(entity_id, opp_id)
            a_id, b_id = sorted([entity_id, opp_id])

            if pair_key not in pair_names:
                pair_names[pair_key] = {
                    "a_id": a_id, "b_id": b_id,
                    "a_name": "", "b_name": "",
                    "entity_type_from_format": None,  # unknown from rankings alone
                }

            for vs_id, vs_data in (opp_data.get("versus") or {}).items():
                # Enforce "versus in only one pair"
                existing = versus_assigned.get(vs_id)
                if existing is not None and existing != pair_key:
                    continue  # belongs to a different pair
                versus_assigned[vs_id] = pair_key

                # Creates zeros entry if absent; no-op if already present from polls
                _ = versus_data[pair_key][vs_id]

                # Track played_at for empty-pair created_at
                played_at = (vs_data or {}).get("played_at") if isinstance(vs_data, dict) else None
                if played_at is not None:
                    cur = pair_last_played.get(pair_key)
                    if cur is None or played_at > cur:
                        pair_last_played[pair_key] = played_at


def aggregate_all(voter_polls: dict, versus_data: dict, pair_names: dict,
                  pair_last_played: dict,
                  rankings: dict, image_fallback: dict, now_ts) -> tuple:
    """
    Pool voters, compute shares, build pair docs.
    Returns (pairs, voters, missing_from_rankings, missing_image).
    """
    voters  = {}
    pair_agg = defaultdict(lambda: {
        "votes_a": 0.0, "votes_b": 0.0, "voter_count": 0,
        "rounds_a": 0, "rounds_b": 0,
        "created_at": None, "last_voted_at": None,
    })

    for (pair_key, voter_id), polls in voter_polls.items():
        agg = pair_agg[pair_key]
        for poll_data in polls.values():
            ts = poll_data["voted_at"]
            if ts is not None:
                if agg["created_at"] is None or ts < agg["created_at"]:
                    agg["created_at"] = ts
                if agg["last_voted_at"] is None or ts > agg["last_voted_at"]:
                    agg["last_voted_at"] = ts

        vdoc = pool_voter_polls(polls)
        vdoc["voter_id"]  = voter_id
        vdoc["pair_key"]  = pair_key
        voters[(pair_key, voter_id)] = vdoc

        agg["rounds_a"] += vdoc["rounds_a"]
        agg["rounds_b"] += vdoc["rounds_b"]
        if vdoc["counted"]:
            agg["votes_a"]    += vdoc["share_a"]
            agg["votes_b"]    += vdoc["share_b"]
            agg["voter_count"] += 1

    all_pair_keys = set(pk for pk, _ in voter_polls.keys()) | set(versus_data.keys())

    missing_from_rankings = []
    missing_image = []
    pairs = {}

    for pair_key in all_pair_keys:
        pnames = pair_names.get(pair_key, {})
        a_id = pnames.get("a_id") or pair_key[:22]
        b_id = pnames.get("b_id") or pair_key[23:]

        entity_a = resolve_entity_info(a_id, rankings, image_fallback, pnames.get("a_name", ""))
        entity_b = resolve_entity_info(b_id, rankings, image_fallback, pnames.get("b_name", ""))

        # entity_type: rankings first, then poll-derived format fallback
        entity_type = None
        if a_id in rankings:
            entity_type = rankings[a_id].get("entity_type")
        if entity_type is None and b_id in rankings:
            entity_type = rankings[b_id].get("entity_type")
        if entity_type is None:
            entity_type = pnames.get("entity_type_from_format")
        if entity_type is None:
            missing_from_rankings.append(pair_key)
            print(f"  [WARN] entity_type=None for pair {pair_key} "
                  f"(a={a_id}, b={b_id})")

        if not entity_a["entity_image"]:
            missing_image.append(f"side_a={a_id} in pair {pair_key}")
        if not entity_b["entity_image"]:
            missing_image.append(f"side_b={b_id} in pair {pair_key}")

        agg    = pair_agg[pair_key]
        versus = {vs_id: dict(v) for vs_id, v in versus_data[pair_key].items()}

        # created_at: earliest poll ts > rankings last_played > now
        created_at = (agg["created_at"]
                      or pair_last_played.get(pair_key)
                      or now_ts)

        pairs[pair_key] = {
            "pair_key":     pair_key,
            "entity_type":  entity_type,
            "entity_ids":   [a_id, b_id],
            "entity_a":     entity_a,
            "entity_b":     entity_b,
            "votes_a":      agg["votes_a"],
            "votes_b":      agg["votes_b"],
            "voter_count":  agg["voter_count"],
            "rounds_a":     agg["rounds_a"],
            "rounds_b":     agg["rounds_b"],
            "versus_count": len(versus),
            "versus":       versus,
            "created_at":   created_at,
            "last_voted_at": agg["last_voted_at"],
        }

    return pairs, voters, missing_from_rankings, missing_image


def run_validation(pairs: dict, voters: dict,
                   poll_pair_keys: dict, all_poll_ids: set) -> list:
    errors = []
    voters_by_pair = defaultdict(dict)
    for (pair_key, voter_id), vdoc in voters.items():
        voters_by_pair[pair_key][voter_id] = vdoc

    for pair_key, pair_doc in pairs.items():
        errors.extend(validate_pair(pair_key, pair_doc, voters_by_pair.get(pair_key, {})))

    for (pair_key, voter_id), vdoc in voters.items():
        for pid in vdoc["polls"]:
            if pid not in all_poll_ids:
                errors.append(
                    f"{pair_key}/voters/{voter_id}: poll_doc_id {pid!r} not in read set"
                )
    return errors


def write_to_firestore(db, pairs: dict, voters: dict, poll_pair_keys: dict):
    write_errors = []
    bw = db.bulk_writer()

    @bw.on_write_error
    def _handle(request, result, exc):
        write_errors.append(f"{getattr(request, 'document', '?').path}: {exc}")
        return False

    for poll_id, pair_key in poll_pair_keys.items():
        bw.update(db.collection("polls").document(poll_id), {"pair_key": pair_key})

    for (pair_key, voter_id), vdoc in voters.items():
        ref = db.collection("pairs").document(pair_key).collection("voters").document(voter_id)
        bw.set(ref, vdoc)

    for pair_key, pair_doc in pairs.items():
        bw.set(db.collection("pairs").document(pair_key), pair_doc)

    bw.close()

    if write_errors:
        print(f"WRITE ERRORS ({len(write_errors)}):")
        for e in write_errors[:30]:
            print(f"  {e}")
        sys.exit(1)

    print(f"BulkWriter done: {len(poll_pair_keys)} poll updates, "
          f"{len(voters)} voter docs, {len(pairs)} pair docs.")


# ─── Diagnostics printing ─────────────────────────────────────────────────────

def print_diagnostics(diag: dict, stats: dict):
    print("\n=== DIAGNOSTICS ===")

    print("\n  Polls by format:")
    for fmt, n in sorted(stats["format_counts"].items()):
        print(f"    {fmt}: {n}")

    print(f"\n  Distinct unusual winner/winner values seen:")
    for v in sorted(diag["winner_values"]):
        print(f"    {v!r}")
    if not diag["winner_values"]:
        print("    (none — all winners matched expected track IDs / Album1 / Album2)")

    cw = diag["comp_with_bonus"]
    cn = diag["comp_no_bonus"]
    print(f"\n  Computed vs stored rounds  [WITH bonus]:")
    print(f"    matches: {cw['match']}  mismatches: {cw['mismatch']}")
    for ex in cw["examples"]:
        print(ex)

    print(f"\n  Computed vs stored rounds  [WITHOUT bonus]:")
    print(f"    matches: {cn['match']}  mismatches: {cn['mismatch']}")
    for ex in cn["examples"]:
        print(ex)

    if diag["prev_zero_vote"]:
        print(f"\n  Polls with stored totals = 0  (were 0-0 in previous run):")
        for entry in diag["prev_zero_vote"]:
            print(f"    poll={entry['poll_id']}  fmt={entry['fmt']}")
            print(f"      computed non-bonus: side1={entry['comp_s1']} side2={entry['comp_s2']}")
            print(f"      bonus: side1+={entry['comp_b1']} side2+={entry['comp_b2']}")
            print(f"      completion_pct={entry['completion_pct']}  td_len={entry['td_len']}")

    print(f"\n  === Worked check: versus={_WORKED_CHECK_VERSUS} voter={_WORKED_CHECK_VOTER} ===")
    if not diag.get("worked_check"):
        print("    NOT FOUND in processed polls")
    else:
        for entry in diag["worked_check"]:
            exp_a = 4
            exp_b = 3
            actual_a = entry["rounds_a_nobonus"]
            actual_b = entry["rounds_b_nobonus"]
            ok = (actual_a == exp_a and actual_b == exp_b)
            print(f"    poll_id: {entry['poll_id']}")
            print(f"    id1={entry['id1']}  id2={entry['id2']}")
            print(f"    a_id={entry['a_id']}  b_id={entry['b_id']}")
            print(f"    computed non-bonus: side1={entry['computed_s1_nobonus']} side2={entry['computed_s2_nobonus']}")
            print(f"    bonus: side1+={entry['computed_b1']} side2+={entry['computed_b2']}")
            print(f"    rounds_a (no bonus) = {actual_a}  rounds_b (no bonus) = {actual_b}")
            print(f"    expected rounds_a=4  rounds_b=3 → {'PASS ✓' if ok else 'FAIL ✗'}")
            print(f"    stored summary: album1_votes={entry['stored1']} album2_votes={entry['stored2']}")
            print(f"    td_len={entry['td_len']}")
            print()


# ─── JSON preview helper ──────────────────────────────────────────────────────

def _to_json_safe(obj):
    if hasattr(obj, "isoformat"):
        return obj.isoformat()
    if isinstance(obj, dict):
        return {k: _to_json_safe(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_to_json_safe(v) for v in obj]
    return obj


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Backfill Firestore `pairs` collection (artist + album formats)."
    )
    parser.add_argument("--commit", action="store_true",
                        help="Write to Firestore (default: dry run)")
    parser.add_argument("--limit", type=int, default=None,
                        help="Process only the first N polls (testing)")
    args = parser.parse_args()

    creds = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", DEFAULT_KEY)
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = creds

    mode = "COMMIT" if args.commit else "DRY RUN"
    print(f"{'='*60}")
    print(f"  backfill_pairs.py — {mode}")
    print(f"  Project:       {PROJECT_ID}")
    print(f"  MIN_ROUNDS:    {MIN_ROUNDS}")
    print(f"  INCLUDE_BONUS: {INCLUDE_BONUS}")
    if args.limit:
        print(f"  Limit:         first {args.limit} polls")
    print(f"{'='*60}\n")

    db = firestore.Client(project=PROJECT_ID)
    now_ts = datetime.now(timezone.utc)

    # Step 1 ──────────────────────────────────────────────────────────────────
    print("Step 1: Loading rankings docs …")
    rankings, image_fallback = load_rankings(db)
    print(f"  {len(rankings)} rankings docs, {len(image_fallback)} image fallback entries\n")

    # Step 2 ──────────────────────────────────────────────────────────────────
    print("Step 2: Streaming polls …")
    polls_ref = db.collection("polls")
    polls_iter = (polls_ref.limit(args.limit) if args.limit else polls_ref).stream()

    all_poll_ids = set()
    (voter_polls, versus_data, pair_names,
     poll_pair_keys, versus_to_pair, stats, diag) = build_in_memory(polls_iter, all_poll_ids)

    print(f"  Read:    {stats['read']}")
    print(f"  Skipped: {stats['skipped']}")
    for reason, count in sorted(stats["skip_reasons"].items()):
        print(f"    [{reason}]: {count}")
    print(f"  Tagged:  {stats['tagged']}")
    for fmt, n in sorted(stats["format_counts"].items()):
        print(f"    {fmt}: {n}")
    print(f"  Zero stored-total polls: {stats['zero_stored_polls']}\n")

    # Step 3 ──────────────────────────────────────────────────────────────────
    print("Step 3: Seeding pairs from rankings opponents …")
    pair_last_played = {}
    seed_from_rankings(versus_data, pair_names, pair_last_played, rankings, versus_to_pair)
    print(f"  versus_data now has {len(versus_data)} pair keys\n")

    # Step 4 ──────────────────────────────────────────────────────────────────
    print("Step 4: Aggregating pairs and voters …")
    pairs, voters, missing_from_rankings, missing_image = aggregate_all(
        voter_polls, versus_data, pair_names,
        pair_last_played, rankings, image_fallback, now_ts
    )
    counted = sum(1 for v in voters.values() if v["counted"])
    pairs_with_votes = sum(1 for p in pairs.values() if p["voter_count"] > 0)
    pairs_zero       = len(pairs) - pairs_with_votes
    print(f"  Pairs: {len(pairs)} total  ({pairs_with_votes} with votes, {pairs_zero} zero-vote)")
    print(f"  Voter docs: {len(voters)} total  ({counted} counted, {len(voters)-counted} not counted)")
    if missing_from_rankings:
        print(f"  [WARN] {len(missing_from_rankings)} pairs with entity_type=None")
    if missing_image:
        print(f"  [WARN] {len(missing_image)} entity sides missing image:")
        for m in missing_image[:20]:
            print(f"    {m}")
    print()

    # Step 5 ──────────────────────────────────────────────────────────────────
    print("Step 5: Validation …")
    errors = run_validation(pairs, voters, poll_pair_keys, all_poll_ids)
    if errors:
        print(f"  VALIDATION FAILED — {len(errors)} error(s):")
        for e in errors:
            print(f"    {e}")
        sys.exit(1)
    print("  All checks PASSED\n")

    # Diagnostics ─────────────────────────────────────────────────────────────
    print_diagnostics(diag, stats)

    # Sample output ───────────────────────────────────────────────────────────
    sample_pk = next(
        (pk for pk, p in pairs.items() if p["voter_count"] > 0),
        next(iter(pairs), None)
    )
    if sample_pk:
        print(f"\n=== Sample pair: {sample_pk} ===")
        print(json.dumps(_to_json_safe(pairs[sample_pk]), indent=2))
        sv = next(((pk, vid) for (pk, vid) in voters if pk == sample_pk), None)
        if sv:
            print(f"\n=== Sample voter: {sv[1]} ===")
            print(json.dumps(_to_json_safe(voters[sv]), indent=2))

    # Summary ─────────────────────────────────────────────────────────────────
    print(f"\n{'='*60}")
    print("  SUMMARY")
    print(f"{'='*60}")
    print(f"  polls read:                  {stats['read']}")
    print(f"  polls skipped:               {stats['skipped']}")
    print(f"  polls tagged with pair_key:  {stats['tagged']}")
    print(f"    artist polls:              {stats['format_counts'].get('artist',0)}")
    print(f"    album  polls:              {stats['format_counts'].get('album',0)}")
    print(f"  pairs (with votes):          {pairs_with_votes}")
    print(f"  pairs (zero votes):          {pairs_zero}")
    print(f"  voter docs total:            {len(voters)}")
    print(f"  voter docs counted:          {counted}")
    print(f"  voter docs not counted:      {len(voters) - counted}")
    print(f"  entities missing type:       {len(missing_from_rankings)}")
    print(f"  entity sides missing image:  {len(missing_image)}")
    print(f"{'='*60}\n")

    if not args.commit:
        preview = {
            "generated_at": now_ts.isoformat(),
            "stats": {
                "polls_read":    stats["read"],
                "polls_tagged":  stats["tagged"],
                "artist_polls":  stats["format_counts"].get("artist", 0),
                "album_polls":   stats["format_counts"].get("album", 0),
                "pairs_total":   len(pairs),
                "voters_total":  len(voters),
                "voters_counted": counted,
            },
            "pairs":  {pk: _to_json_safe(p) for pk, p in pairs.items()},
            "voters": {
                f"{pk}||{vid}": _to_json_safe(v)
                for (pk, vid), v in voters.items()
            },
            "poll_pair_keys": poll_pair_keys,
        }
        with open("backfill_preview.json", "w") as f:
            json.dump(preview, f, indent=2)
        print(f"DRY RUN complete. Preview → backfill_preview.json")
        print("To commit: python3 backfill_pairs.py --commit\n")
    else:
        print("Writing to Firestore …")
        write_to_firestore(db, pairs, voters, poll_pair_keys)
        print("Commit complete.\n")


if __name__ == "__main__":
    main()
