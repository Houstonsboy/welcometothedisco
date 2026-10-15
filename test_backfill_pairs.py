#!/usr/bin/env python3
"""
Unit tests for the pure aggregation logic in backfill_pairs.py.

Tests use the worked example from the spec (in-memory only, no Firestore).
Rounds are always computed from track_details (stored votes are ignored).

Rocky = "13ubrt8QOOCPljQ2FL1Kca"  (side a — lex lower)
Uzi   = "4O15NlyKLIASxsJ0PrXPfz"  (side b — lex higher)

Polls (rounds computed from mock track_details):
  poll-1  voter G,  versus TY9...: artist1=Uzi  side1=1, artist2=Rocky side2=3 → a=3, b=1
  poll-2  voter G,  versus Kp4...: artist1=Rocky side1=1, artist2=Uzi  side2=2 → a=1, b=2
  poll-3  voter U2, versus TY9...: artist1=Rocky side1=1, artist2=Uzi  side2=3 → a=1, b=3

Expected voter/G:  rounds_a=4, rounds_b=3, share_a=4/7, share_b=3/7, counted=True
Expected voter/U2: rounds_a=1, rounds_b=3, share_a=1/4, share_b=3/4, counted=True
Expected pair:     votes_a=23/28≈0.8214, votes_b=33/28≈1.1786,
                   voter_count=2, rounds_a=5, rounds_b=6,
                   versus_count=2
  versus[TY9DFG…]  = {rounds_a:4, rounds_b:4, poll_count:2}
  versus[Kp4xR8…]  = {rounds_a:1, rounds_b:2, poll_count:1}
"""

import sys
import unittest
from datetime import datetime, timezone

from backfill_pairs import (
    make_pair_key,
    map_rounds_to_ab,
    compute_voter_shares,
    pool_voter_polls,
    validate_pair,
    build_in_memory,
    aggregate_all,
    run_validation,
    detect_format,
    compute_rounds_from_track_details,
    MIN_ROUNDS,
)

ROCKY = "13ubrt8QOOCPljQ2FL1Kca"
UZI   = "4O15NlyKLIASxsJ0PrXPfz"
PAIR_KEY = f"{ROCKY}_{UZI}"
VS1 = "TY9DFGNh24IUsBhDV6dc"
VS2 = "Kp4xR8mQ2vLn7TbW9sYe"
TS1 = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
TS2 = datetime(2026, 1, 2, 12, 0, 0, tzinfo=timezone.utc)
TS3 = datetime(2026, 1, 3, 12, 0, 0, tzinfo=timezone.utc)

# Track IDs used in mock track_details
T_UZI   = "uzi_track_000000000000"
T_ROCKY = "rocky_track_00000000000"


def _artist_round(winner_id, a1_id, a2_id, is_bonus=False):
    return {"Winner": winner_id, "artist1trackID": a1_id, "artist2trackID": a2_id, "isBonus": is_bonus}


def _make_track_details_artist(a1_id, a1_wins, a2_id, a2_wins):
    """Build a mock ARTIST track_details dict with the requested win counts."""
    rounds = {}
    i = 0
    for _ in range(a1_wins):
        rounds[str(i)] = _artist_round(a1_id, a1_id, a2_id)
        i += 1
    for _ in range(a2_wins):
        rounds[str(i)] = _artist_round(a2_id, a1_id, a2_id)
        i += 1
    return rounds


class MockDoc:
    """Minimal stand-in for a Firestore DocumentSnapshot."""
    def __init__(self, doc_id: str, data: dict):
        self.id = doc_id
        self._data = data

    def to_dict(self):
        return dict(self._data)


def _make_poll_docs():
    return [
        # poll-1: artist1=UZI gets 1, artist2=ROCKY gets 3 → side1=1, side2=3
        MockDoc("poll-1", {
            "voter_id": "G", "versus_id": VS1,
            "artist1ID": UZI,   "artist1Name": "Lil Uzi Vert",
            "artist2ID": ROCKY, "artist2Name": "A$AP Rocky",
            "timestamp": TS1,
            "track_details": _make_track_details_artist(T_UZI, 1, T_ROCKY, 3),
        }),
        # poll-2: artist1=ROCKY gets 1, artist2=UZI gets 2 → side1=1, side2=2
        MockDoc("poll-2", {
            "voter_id": "G", "versus_id": VS2,
            "artist1ID": ROCKY, "artist1Name": "A$AP Rocky",
            "artist2ID": UZI,   "artist2Name": "Lil Uzi Vert",
            "timestamp": TS2,
            "track_details": _make_track_details_artist(T_ROCKY, 1, T_UZI, 2),
        }),
        # poll-3: artist1=ROCKY gets 1, artist2=UZI gets 3 → side1=1, side2=3
        MockDoc("poll-3", {
            "voter_id": "U2", "versus_id": VS1,
            "artist1ID": ROCKY, "artist1Name": "A$AP Rocky",
            "artist2ID": UZI,   "artist2Name": "Lil Uzi Vert",
            "timestamp": TS3,
            "track_details": _make_track_details_artist(T_ROCKY, 1, T_UZI, 3),
        }),
    ]


class TestPairKey(unittest.TestCase):
    def test_lower_first(self):
        self.assertEqual(make_pair_key(ROCKY, UZI), PAIR_KEY)

    def test_commutative(self):
        self.assertEqual(make_pair_key(UZI, ROCKY), make_pair_key(ROCKY, UZI))

    def test_same_result_either_order(self):
        self.assertEqual(make_pair_key(ROCKY, UZI), PAIR_KEY)
        self.assertEqual(make_pair_key(UZI, ROCKY), PAIR_KEY)


class TestMapRoundsToAB(unittest.TestCase):
    def test_artist1_is_lower(self):
        # ROCKY < UZI; artist1=ROCKY → a=artist1_side, b=artist2_side
        a, b = map_rounds_to_ab(ROCKY, 3, UZI, 1)
        self.assertEqual(a, 3)
        self.assertEqual(b, 1)

    def test_artist1_is_higher(self):
        # artist1=UZI (higher) → a=artist2_side (Rocky's), b=artist1_side (Uzi's)
        a, b = map_rounds_to_ab(UZI, 1, ROCKY, 3)
        self.assertEqual(a, 3)   # Rocky (side a) gets 3
        self.assertEqual(b, 1)   # Uzi (side b) gets 1


class TestComputeVoterShares(unittest.TestCase):
    def test_counted(self):
        sa, sb, counted = compute_voter_shares(4, 3)
        self.assertTrue(counted)
        self.assertAlmostEqual(sa, 4/7)
        self.assertAlmostEqual(sb, 3/7)
        self.assertAlmostEqual(sa + sb, 1.0)

    def test_zero_rounds_not_counted(self):
        sa, sb, counted = compute_voter_shares(0, 0)
        self.assertFalse(counted)
        self.assertEqual(sa, 0.0)
        self.assertEqual(sb, 0.0)

    def test_min_rounds_boundary(self):
        # MIN_ROUNDS == 1: exactly 1 total → counted
        sa, sb, counted = compute_voter_shares(1, 0)
        self.assertTrue(counted)
        self.assertAlmostEqual(sa, 1.0)
        self.assertAlmostEqual(sb, 0.0)


class TestDetectFormat(unittest.TestCase):
    def test_artist_format(self):
        self.assertEqual(detect_format({"artist1ID": "x"}), "artist")

    def test_album_format(self):
        self.assertEqual(detect_format({"album1_id": "x"}), "album")

    def test_unknown_format(self):
        self.assertIsNone(detect_format({"album1ID": "x"}))  # camelCase without underscore

    def test_album_takes_priority(self):
        # album1_id wins if both keys exist
        self.assertEqual(detect_format({"album1_id": "x", "artist1ID": "y"}), "album")


class TestComputeRoundsFromTrackDetails(unittest.TestCase):
    def _diag(self):
        return {"winner_values": set()}

    def test_artist_basic(self):
        td = _make_track_details_artist(T_UZI, 2, T_ROCKY, 3)
        s1, s2, b1, b2 = compute_rounds_from_track_details(td, "artist", self._diag())
        self.assertEqual(s1, 2)
        self.assertEqual(s2, 3)
        self.assertEqual(b1, 0)
        self.assertEqual(b2, 0)

    def test_artist_bonus_excluded(self):
        td = {
            "0": _artist_round(T_UZI, T_UZI, T_ROCKY, is_bonus=False),
            "1": _artist_round(T_ROCKY, T_UZI, T_ROCKY, is_bonus=True),
        }
        s1, s2, b1, b2 = compute_rounds_from_track_details(td, "artist", self._diag())
        self.assertEqual(s1, 1)   # non-bonus UZI win
        self.assertEqual(s2, 0)
        self.assertEqual(b1, 0)
        self.assertEqual(b2, 1)   # bonus ROCKY win

    def test_artist_empty_winner_ignored(self):
        td = {"0": {"Winner": "", "artist1trackID": T_UZI, "artist2trackID": T_ROCKY, "isBonus": False}}
        s1, s2, b1, b2 = compute_rounds_from_track_details(td, "artist", self._diag())
        self.assertEqual(s1, 0)
        self.assertEqual(s2, 0)

    def test_artist_empty_track_details(self):
        s1, s2, b1, b2 = compute_rounds_from_track_details({}, "artist", self._diag())
        self.assertEqual(s1 + s2 + b1 + b2, 0)

    def test_artist_none_track_details(self):
        s1, s2, b1, b2 = compute_rounds_from_track_details(None, "artist", self._diag())
        self.assertEqual(s1 + s2 + b1 + b2, 0)

    def test_album_basic(self):
        td = [
            {"winner": "Album1", "isBonus": False},
            {"winner": "Album2", "isBonus": False},
            {"winner": "Album2", "isBonus": False},
        ]
        s1, s2, b1, b2 = compute_rounds_from_track_details(td, "album", self._diag())
        self.assertEqual(s1, 1)
        self.assertEqual(s2, 2)
        self.assertEqual(b1 + b2, 0)

    def test_album_bonus_separated(self):
        td = [
            {"winner": "Album1", "isBonus": False},
            {"winner": "Album2", "isBonus": False},
            {"winner": "Album1", "isBonus": True},
        ]
        s1, s2, b1, b2 = compute_rounds_from_track_details(td, "album", self._diag())
        self.assertEqual(s1, 1)
        self.assertEqual(s2, 1)
        self.assertEqual(b1, 1)
        self.assertEqual(b2, 0)

    def test_album_unusual_winner_logged(self):
        d = self._diag()
        td = [{"winner": "Tie", "isBonus": False}]
        compute_rounds_from_track_details(td, "album", d)
        self.assertTrue(any("Tie" in v for v in d["winner_values"]))


class TestWorkedExample(unittest.TestCase):
    """End-to-end test of the worked example using only in-memory functions."""

    def setUp(self):
        polls = _make_poll_docs()
        all_poll_ids = set()
        (voter_polls, versus_data, pair_names,
         poll_pair_keys, versus_to_pair, stats, diag) = build_in_memory(iter(polls), all_poll_ids)
        self.voter_polls = voter_polls
        self.versus_data = versus_data
        self.pair_names = pair_names
        self.poll_pair_keys = poll_pair_keys
        self.versus_to_pair = versus_to_pair
        self.all_poll_ids = all_poll_ids
        self.stats = stats

        now_ts = datetime(2026, 1, 4, tzinfo=timezone.utc)
        pairs, voters, missing_type, missing_img = aggregate_all(
            voter_polls, versus_data, pair_names,
            {}, {}, {}, now_ts   # pair_last_played={}, rankings={}, image_fallback={}
        )
        self.pairs = pairs
        self.voters = voters

    # ── poll ingestion ───────────────────────────────────────────────────────

    def test_polls_read_and_tagged(self):
        self.assertEqual(self.stats["read"], 3)
        self.assertEqual(self.stats["tagged"], 3)
        self.assertEqual(self.stats["skipped"], 0)

    def test_format_count_artist(self):
        self.assertEqual(self.stats["format_counts"]["artist"], 3)

    def test_pair_key_in_poll_pair_keys(self):
        self.assertIn("poll-1", self.poll_pair_keys)
        self.assertEqual(self.poll_pair_keys["poll-1"], PAIR_KEY)

    def test_versus_to_pair(self):
        self.assertEqual(self.versus_to_pair[VS1], PAIR_KEY)
        self.assertEqual(self.versus_to_pair[VS2], PAIR_KEY)

    # ── voter G ──────────────────────────────────────────────────────────────

    def test_voter_G_rounds(self):
        vdoc = self.voters[(PAIR_KEY, "G")]
        self.assertEqual(vdoc["rounds_a"], 4)  # poll-1 a=3 + poll-2 a=1
        self.assertEqual(vdoc["rounds_b"], 3)  # poll-1 b=1 + poll-2 b=2

    def test_voter_G_shares(self):
        vdoc = self.voters[(PAIR_KEY, "G")]
        self.assertTrue(vdoc["counted"])
        self.assertAlmostEqual(vdoc["share_a"], 4/7)
        self.assertAlmostEqual(vdoc["share_b"], 3/7)
        self.assertAlmostEqual(vdoc["share_a"] + vdoc["share_b"], 1.0)

    def test_voter_G_polls_keyed_by_doc_id(self):
        vdoc = self.voters[(PAIR_KEY, "G")]
        self.assertIn("poll-1", vdoc["polls"])
        self.assertIn("poll-2", vdoc["polls"])
        self.assertNotIn("poll-3", vdoc["polls"])

    def test_voter_G_poll1_entry(self):
        entry = self.voters[(PAIR_KEY, "G")]["polls"]["poll-1"]
        self.assertEqual(entry["versus_id"], VS1)
        # poll-1: artist1=UZI (side1=1), artist2=ROCKY (side2=3)
        # map_rounds_to_ab(UZI, 1, ROCKY, 3): UZI>ROCKY → rounds_a=side2=3, rounds_b=side1=1
        self.assertEqual(entry["rounds_a"], 3)
        self.assertEqual(entry["rounds_b"], 1)

    # ── voter U2 ─────────────────────────────────────────────────────────────

    def test_voter_U2_rounds(self):
        vdoc = self.voters[(PAIR_KEY, "U2")]
        self.assertEqual(vdoc["rounds_a"], 1)
        self.assertEqual(vdoc["rounds_b"], 3)

    def test_voter_U2_shares(self):
        vdoc = self.voters[(PAIR_KEY, "U2")]
        self.assertTrue(vdoc["counted"])
        self.assertAlmostEqual(vdoc["share_a"], 1/4)
        self.assertAlmostEqual(vdoc["share_b"], 3/4)

    # ── pair doc ─────────────────────────────────────────────────────────────

    def test_pair_exists(self):
        self.assertIn(PAIR_KEY, self.pairs)

    def test_pair_votes(self):
        p = self.pairs[PAIR_KEY]
        self.assertAlmostEqual(p["votes_a"], 4/7 + 1/4)   # ≈ 0.8214
        self.assertAlmostEqual(p["votes_b"], 3/7 + 3/4)   # ≈ 1.1786
        self.assertAlmostEqual(p["votes_a"] + p["votes_b"], 2.0)

    def test_pair_voter_count(self):
        self.assertEqual(self.pairs[PAIR_KEY]["voter_count"], 2)

    def test_pair_rounds(self):
        p = self.pairs[PAIR_KEY]
        self.assertEqual(p["rounds_a"], 5)
        self.assertEqual(p["rounds_b"], 6)

    def test_pair_versus_count(self):
        p = self.pairs[PAIR_KEY]
        self.assertEqual(p["versus_count"], 2)
        self.assertIn(VS1, p["versus"])
        self.assertIn(VS2, p["versus"])

    def test_pair_versus_TY9(self):
        v = self.pairs[PAIR_KEY]["versus"][VS1]
        self.assertEqual(v["rounds_a"], 4)  # poll-1 a=3 + poll-3 a=1
        self.assertEqual(v["rounds_b"], 4)  # poll-1 b=1 + poll-3 b=3
        self.assertEqual(v["poll_count"], 2)

    def test_pair_versus_Kp4(self):
        v = self.pairs[PAIR_KEY]["versus"][VS2]
        self.assertEqual(v["rounds_a"], 1)
        self.assertEqual(v["rounds_b"], 2)
        self.assertEqual(v["poll_count"], 1)

    def test_pair_entity_ids_ordered(self):
        p = self.pairs[PAIR_KEY]
        self.assertEqual(p["entity_ids"], [ROCKY, UZI])

    def test_pair_timestamps(self):
        p = self.pairs[PAIR_KEY]
        self.assertEqual(p["created_at"], TS1)   # earliest poll timestamp
        self.assertEqual(p["last_voted_at"], TS3) # latest poll timestamp

    # ── validation ───────────────────────────────────────────────────────────

    def test_validation_passes(self):
        errors = run_validation(self.pairs, self.voters, self.poll_pair_keys, self.all_poll_ids)
        self.assertEqual(errors, [], msg="\n".join(errors))


class TestUncountedVoter(unittest.TestCase):
    """A voter with 0 total rounds must not be counted and must have shares = 0."""

    def test_zero_rounds_not_counted(self):
        # poll has no track_details → compute_rounds returns (0,0,0,0) → rounds_a=0, rounds_b=0
        poll = MockDoc("poll-z", {
            "voter_id": "ZeroGuy", "versus_id": "vsX",
            "artist1ID": ROCKY,
            "artist2ID": UZI,
            "timestamp": TS1,
        })
        all_poll_ids = set()
        (voter_polls, versus_data, pair_names,
         _, _, stats, _) = build_in_memory(iter([poll]), all_poll_ids)

        now_ts = datetime(2026, 1, 4, tzinfo=timezone.utc)
        pairs, voters, _, _ = aggregate_all(
            voter_polls, versus_data, pair_names, {}, {}, {}, now_ts
        )

        vdoc = voters[(PAIR_KEY, "ZeroGuy")]
        self.assertFalse(vdoc["counted"])
        self.assertEqual(vdoc["share_a"], 0.0)
        self.assertEqual(vdoc["share_b"], 0.0)
        self.assertEqual(pairs[PAIR_KEY]["voter_count"], 0)
        self.assertEqual(pairs[PAIR_KEY]["rounds_a"], 0)
        self.assertEqual(pairs[PAIR_KEY]["rounds_b"], 0)


class TestSkipConditions(unittest.TestCase):
    """Polls with missing/degenerate fields must be skipped."""

    def _run(self, data):
        doc = MockDoc("skip-test", data)
        all_poll_ids = set()
        (_, _, _, poll_pair_keys, _, stats, _) = build_in_memory(iter([doc]), all_poll_ids)
        return stats, poll_pair_keys

    def test_skip_missing_voter_id(self):
        stats, ppk = self._run({
            "versus_id": "v1", "artist1ID": ROCKY, "artist2ID": UZI,
        })
        self.assertEqual(stats["skipped"], 1)
        self.assertNotIn("skip-test", ppk)

    def test_skip_same_artist_ids(self):
        stats, ppk = self._run({
            "voter_id": "u1", "versus_id": "v1",
            "artist1ID": ROCKY, "artist2ID": ROCKY,
        })
        self.assertEqual(stats["skipped"], 1)
        self.assertNotIn("skip-test", ppk)

    def test_skip_missing_versus_id(self):
        stats, ppk = self._run({
            "voter_id": "u1", "artist1ID": ROCKY, "artist2ID": UZI,
        })
        self.assertEqual(stats["skipped"], 1)

    def test_skip_unknown_format(self):
        # camelCase album1ID (no underscore) → unknown format → skip
        stats, ppk = self._run({
            "voter_id": "u1", "versus_id": "v1",
            "album1ID": ROCKY, "album2ID": UZI,
        })
        self.assertEqual(stats["skipped"], 1)

    def test_artist_format_detected(self):
        stats, ppk = self._run({
            "voter_id": "u1", "versus_id": "v1",
            "artist1ID": ROCKY, "artist2ID": UZI,
        })
        self.assertEqual(stats["skipped"], 0)
        self.assertEqual(stats["tagged"], 1)

    def test_album_format_detected(self):
        stats, ppk = self._run({
            "voter_id": "u1", "versus_id": "v1",
            "album1_id": ROCKY, "album2_id": UZI,
        })
        self.assertEqual(stats["skipped"], 0)
        self.assertEqual(stats["tagged"], 1)


class TestAlbumPollRounds(unittest.TestCase):
    """Album format polls: rounds computed from track_details list."""

    ALBUM_A = "4qZBW3f2Q8y0k1A84d4iAO"  # My Dear Melancholy, (lex lower → side a)
    ALBUM_B = "7zCODUHkfuRxsUjtuzNqbd"  # House Of Balloons (lex higher → side b)

    def _make_album_td(self, album1_wins, album2_wins, bonus_album1=0, bonus_album2=0):
        """album1=ALBUM_B (HoB), album2=ALBUM_A (MDM) in the worked check poll."""
        td = []
        for _ in range(album1_wins):
            td.append({"winner": "Album1", "isBonus": False})
        for _ in range(album2_wins):
            td.append({"winner": "Album2", "isBonus": False})
        for _ in range(bonus_album1):
            td.append({"winner": "Album1", "isBonus": True})
        for _ in range(bonus_album2):
            td.append({"winner": "Album2", "isBonus": True})
        return td

    def test_album_rounds_basic(self):
        td = self._make_album_td(3, 4)   # album1=3, album2=4 non-bonus
        diag = {"winner_values": set()}
        s1, s2, b1, b2 = compute_rounds_from_track_details(td, "album", diag)
        self.assertEqual(s1, 3)
        self.assertEqual(s2, 4)
        self.assertEqual(b1, 0)
        self.assertEqual(b2, 0)

    def test_album_bonus_separated(self):
        td = self._make_album_td(3, 4, bonus_album1=3)
        diag = {"winner_values": set()}
        s1, s2, b1, b2 = compute_rounds_from_track_details(td, "album", diag)
        self.assertEqual(s1, 3)
        self.assertEqual(s2, 4)
        self.assertEqual(b1, 3)
        self.assertEqual(b2, 0)

    def test_album_map_to_ab(self):
        # Worked-check scenario:
        # album1_id = ALBUM_B (HoB, "7zC..."), album2_id = ALBUM_A (MDM, "4qZ...")
        # ALBUM_A < ALBUM_B → a=ALBUM_A (MDM), b=ALBUM_B (HoB)
        # s1=album1(HoB)=3, s2=album2(MDM)=4
        # map_rounds_to_ab(id1=ALBUM_B, s1=3, id2=ALBUM_A, s2=4)
        # id1=ALBUM_B > id2=ALBUM_A → rounds_a=s2=4, rounds_b=s1=3
        a, b = map_rounds_to_ab(self.ALBUM_B, 3, self.ALBUM_A, 4)
        self.assertEqual(a, 4)  # MDM (side a) wins 4
        self.assertEqual(b, 3)  # HoB (side b) wins 3

    def test_album_share_calculation(self):
        sa, sb, counted = compute_voter_shares(4, 3)
        self.assertTrue(counted)
        self.assertAlmostEqual(sa, 4/7)    # ≈ 0.5714
        self.assertAlmostEqual(sb, 3/7)    # ≈ 0.4286

    def test_album_end_to_end(self):
        """Full pipeline for a single album poll."""
        # album1_id = ALBUM_B (HoB), album2_id = ALBUM_A (MDM)
        # HoB wins 3 non-bonus, MDM wins 4 non-bonus, 3 bonus for HoB
        td = self._make_album_td(3, 4, bonus_album1=3)
        poll = MockDoc("worked-check-poll", {
            "voter_id": "voter1", "versus_id": "vs1",
            "album1_id": self.ALBUM_B, "album1_name": "House Of Balloons",
            "album2_id": self.ALBUM_A, "album2_name": "My Dear Melancholy,",
            "track_details": td,
            "summary": {"album1_votes": 5, "album2_votes": 4},
        })
        all_poll_ids = set()
        (voter_polls, versus_data, pair_names,
         poll_pair_keys, _, _, _) = build_in_memory(iter([poll]), all_poll_ids)

        pair_key = make_pair_key(self.ALBUM_B, self.ALBUM_A)
        self.assertIn(pair_key, versus_data)
        self.assertIn("vs1", versus_data[pair_key])

        now_ts = datetime(2026, 1, 4, tzinfo=timezone.utc)
        pairs, voters, _, _ = aggregate_all(
            voter_polls, versus_data, pair_names, {}, {}, {}, now_ts
        )
        p = pairs[pair_key]
        # INCLUDE_BONUS=False: only non-bonus (s1=3, s2=4)
        # rounds_a = MDM=album2=4, rounds_b = HoB=album1=3
        self.assertEqual(p["rounds_a"], 4)
        self.assertEqual(p["rounds_b"], 3)
        vdoc = voters[(pair_key, "voter1")]
        self.assertEqual(vdoc["rounds_a"], 4)
        self.assertEqual(vdoc["rounds_b"], 3)
        self.assertAlmostEqual(vdoc["share_a"], 4/7)
        self.assertAlmostEqual(vdoc["share_b"], 3/7)
        self.assertTrue(vdoc["counted"])


class TestPairLastPlayedCreatedAt(unittest.TestCase):
    """Empty pairs (no polls) should use pair_last_played for created_at."""

    def test_empty_pair_uses_last_played(self):
        from collections import defaultdict
        from backfill_pairs import _make_vs_entry

        pair_key = make_pair_key(ROCKY, UZI)
        last_ts = datetime(2025, 6, 15, tzinfo=timezone.utc)
        now_ts  = datetime(2026, 1, 4, tzinfo=timezone.utc)

        # Simulate an empty pair (seeded from rankings only, no polls)
        voter_polls = {}
        versus_data = defaultdict(lambda: defaultdict(_make_vs_entry))
        versus_data[pair_key]["vs-empty"]  # creates zeros entry

        pair_names = {
            pair_key: {
                "a_id": ROCKY, "b_id": UZI,
                "a_name": "", "b_name": "",
                "entity_type_from_format": None,
            }
        }
        pair_last_played = {pair_key: last_ts}

        pairs, _, _, _ = aggregate_all(
            voter_polls, versus_data, pair_names,
            pair_last_played, {}, {}, now_ts
        )
        self.assertEqual(pairs[pair_key]["created_at"], last_ts)


if __name__ == "__main__":
    unittest.main(verbosity=2)
