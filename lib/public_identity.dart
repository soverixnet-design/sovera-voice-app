import 'dart:async';
import 'package:flutter/widgets.dart';

/// Display identifiers never replace the immutable authentication/account key.
String? activeVipId(Map<String, dynamic>? profile, {DateTime? now}) {
  final id = profile?['vip_id']?.toString().trim();
  if (id == null || !RegExp(r'^\d{1,7}$').hasMatch(id)) return null;
  final raw = profile?['vip_expires_at'];
  // Null is a legacy/lifetime assignment; timed grants must set an expiry.
  if (raw == null) return id;
  final expiry = DateTime.tryParse(raw.toString());
  if (expiry == null || !expiry.isAfter((now ?? DateTime.now()).toUtc())) return null;
  return id;
}

String publicIdentity(Map<String, dynamic>? profile, {DateTime? now}) =>
    activeVipId(profile, now: now) ?? profile?['uid']?.toString() ?? '';

bool matchesPublicIdentity(Map<String, dynamic> profile, String query,
    {DateTime? now}) => publicIdentity(profile, now: now) == query.trim();

/// Refresh identity labels on an open screen after a timed grant expires.
mixin VipExpiryRefresh<T extends StatefulWidget> on State<T> {
  Timer? _identityTimer;
  String get identityRevision;
  String? _lastIdentity;
  @override
  void initState() {
    super.initState();
    _identityTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = identityRevision;
      if (_lastIdentity != next) {
        _lastIdentity = next;
        if (mounted) setState(() {});
      }
    });
  }
  @override
  void dispose() {
    _identityTimer?.cancel();
    super.dispose();
  }
}
