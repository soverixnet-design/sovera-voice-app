import 'package:flutter_test/flutter_test.dart';
import 'package:sovera/public_identity.dart';
void main() {
  final now = DateTime.utc(2026, 10, 19);
  test('active VIP replaces the displayed and searchable original ID', () {
    final p = {'uid': 10000001, 'vip_id': '77', 'vip_expires_at': '2026-10-20T00:00:00Z'};
    expect(publicIdentity(p, now: now), '77');
    expect(matchesPublicIdentity(p, '77', now: now), isTrue);
    expect(matchesPublicIdentity(p, '10000001', now: now), isFalse);
    expect(p['uid'], 10000001);
  });
  test('expiry boundary restores original ID and removes VIP search match', () {
    final p = {'uid': 10000001, 'vip_id': '77', 'vip_expires_at': '2026-10-19T00:00:00Z'};
    expect(publicIdentity(p, now: now), '10000001');
    expect(matchesPublicIdentity(p, '77', now: now), isFalse);
  });
  test('invalid expiry fails closed and lifetime legacy grants remain valid', () {
    expect(publicIdentity({'uid': 9, 'vip_id': '7', 'vip_expires_at': 'bad'}, now: now), '9');
    expect(publicIdentity({'uid': 9, 'vip_id': '7'}, now: now), '7');
  });
}
