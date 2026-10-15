// test/pair_utils_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:welcometothedisco/utils/pair_utils.dart';

void main() {
  // ── makePairKey ─────────────────────────────────────────────────────────────

  group('makePairKey', () {
    test('lower-lex ID is always the a-side', () {
      expect(makePairKey('aaa', 'bbb'), equals('aaa_bbb'));
      expect(makePairKey('bbb', 'aaa'), equals('aaa_bbb'));
    });

    test('commutative — argument order does not matter', () {
      const id1 = 'spotify:artist:111';
      const id2 = 'spotify:artist:222';
      expect(makePairKey(id1, id2), equals(makePairKey(id2, id1)));
    });

    test('trims surrounding whitespace before sorting', () {
      expect(makePairKey('  bbb  ', 'aaa'), equals('aaa_bbb'));
    });

    test('IDs that are already equal produce a stable key', () {
      expect(makePairKey('x', 'x'), equals('x_x'));
    });

    test('lexicographic (not numeric) sort', () {
      // "9" > "10" lexicographically
      expect(makePairKey('9', '10'), equals('10_9'));
    });

    test('Spotify-style IDs', () {
      const a = 'spotify:album:AAAA';
      const z = 'spotify:album:ZZZZ';
      expect(makePairKey(a, z), equals('spotify:album:AAAA_spotify:album:ZZZZ'));
      expect(makePairKey(z, a), equals('spotify:album:AAAA_spotify:album:ZZZZ'));
    });
  });

  // ── entitySide ──────────────────────────────────────────────────────────────

  group('entitySide', () {
    test('entity that is a-side returns "a"', () {
      expect(entitySide('aaa', 'aaa_bbb'), equals('a'));
    });

    test('entity that is b-side returns "b"', () {
      expect(entitySide('bbb', 'aaa_bbb'), equals('b'));
    });
  });

  // ── mapRoundsToAB ───────────────────────────────────────────────────────────

  group('mapRoundsToAB (a/b mapping mirrors Jest suite)', () {
    test('entity1 is a-side → rounds stay in same order', () {
      // pairKey = "aaa_bbb", entity1 = "aaa" = a-side
      final (a, b) = mapRoundsToAB('aaa', 'aaa_bbb', 3, 1);
      expect(a, equals(3));
      expect(b, equals(1));
    });

    test('entity1 is b-side → rounds are swapped', () {
      // pairKey = "aaa_bbb", entity1 = "bbb" = b-side
      final (a, b) = mapRoundsToAB('bbb', 'aaa_bbb', 3, 1);
      // entity1=bbb won 3 → b-side gets 3; entity2=aaa won 1 → a-side gets 1
      expect(a, equals(1));
      expect(b, equals(3));
    });

    test('entity1 ID is trimmed before comparison', () {
      final (a, b) = mapRoundsToAB('  aaa  ', 'aaa_bbb', 2, 0);
      expect(a, equals(2));
      expect(b, equals(0));
    });

    test('zeros propagate correctly', () {
      final (a, b) = mapRoundsToAB('aaa', 'aaa_bbb', 0, 0);
      expect(a, equals(0));
      expect(b, equals(0));
    });

    test('Spotify-style ID a/b mapping', () {
      const a1 = 'spotify:artist:AAAA';
      const z1 = 'spotify:artist:ZZZZ';
      final pairKey = makePairKey(a1, z1);
      // AAAA < ZZZZ → AAAA is a-side
      // entity1 = ZZZZ = b-side → entity1's wins go to b, entity2's to a
      final (ra, rb) = mapRoundsToAB(z1, pairKey, 2, 0);
      expect(ra, equals(0)); // AAAA (a-side) got 0
      expect(rb, equals(2)); // ZZZZ (b-side) got 2
    });
  });

  // ── computeRoundCounts ──────────────────────────────────────────────────────

  group('computeRoundCounts', () {
    test('counts entity1 and entity2 wins, skips bonus and null', () {
      final td = [
        {'winner': 'entity1', 'isBonus': false},
        {'winner': 'entity1', 'isBonus': false},
        {'winner': 'entity2', 'isBonus': false},
        {'winner': null},
        {'winner': 'entity1', 'isBonus': true}, // bonus — excluded
      ];
      final (r1, r2) = computeRoundCounts(td);
      expect(r1, equals(2));
      expect(r2, equals(1));
    });

    test('empty list returns zeros', () {
      final (r1, r2) = computeRoundCounts([]);
      expect(r1, equals(0));
      expect(r2, equals(0));
    });
  });

  // ── computeShares ───────────────────────────────────────────────────────────

  group('computeShares', () {
    test('returns 0/0 when total is zero', () {
      final (sa, sb) = computeShares(0, 0);
      expect(sa, equals(0.0));
      expect(sb, equals(0.0));
    });

    test('returns correct percentages', () {
      final (sa, sb) = computeShares(3, 1);
      expect(sa, closeTo(75.0, 0.001));
      expect(sb, closeTo(25.0, 0.001));
    });
  });
}
