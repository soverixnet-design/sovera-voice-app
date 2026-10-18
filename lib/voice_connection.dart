import 'dart:convert';
import 'package:http/http.dart' as http;

const voiceTokenEndpoint = 'https://voice.soverixnet.com/sovera/token';
const voiceServerUrl = 'wss://voice.soverixnet.com';

class VoiceConnectionException implements Exception {
  final String message;
  const VoiceConnectionException(this.message);
  @override
  String toString() => message;
}

class VoiceCredentials {
  final String url, token;
  const VoiceCredentials(this.url, this.token);
}

/// Only a logged-in session can request a room-scoped token. No API secret is
/// stored in the app, and response bodies/tokens never become error messages.
Future<VoiceCredentials> requestVoiceCredentials({
  required String roomId,
  required String? accessToken,
  http.Client? client,
}) async {
  if (accessToken == null || accessToken.isEmpty) {
    throw const VoiceConnectionException('Sign in to join live audio.');
  }
  final transport = client ?? http.Client();
  try {
    final response = await transport.post(Uri.parse(voiceTokenEndpoint),
      headers: {'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json'},
      body: jsonEncode({'room_id': roomId}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 401) {
      throw const VoiceConnectionException('Sign in again to join live audio.');
    }
    if (response.statusCode == 403) {
      throw const VoiceConnectionException('Live audio is unavailable for this account or room.');
    }
    if (response.statusCode != 200) {
      throw const VoiceConnectionException('Voice server unavailable. Tap Retry.');
    }
    final data = jsonDecode(response.body);
    if (data is! Map || data['url'] != voiceServerUrl ||
        data['token'] is! String || (data['token'] as String).isEmpty) {
      throw const VoiceConnectionException('Invalid voice server response.');
    }
    return VoiceCredentials(voiceServerUrl, data['token'] as String);
  } on VoiceConnectionException {
    rethrow;
  } catch (_) {
    throw const VoiceConnectionException('Could not connect to voice. Tap Retry.');
  } finally {
    if (client == null) transport.close();
  }
}

class VoiceSeatState {
  final int count;
  final int? mine;
  final Map<int, String> occupants;
  const VoiceSeatState(this.count, this.mine, this.occupants);

  factory VoiceSeatState.parse(dynamic data) {
    if (data is! Map || data['seat_count'] is! int || data['seats'] is! List) {
      throw const VoiceConnectionException('Invalid seat server response.');
    }
    final count = data['seat_count'] as int;
    final mine = data['my_seat'];
    if (count < 1 || count > 100 || (mine != null && (mine is! int || mine < 0 || mine >= count))) {
      throw const VoiceConnectionException('Invalid seat server response.');
    }
    final occupants = <int, String>{};
    for (final item in data['seats'] as List) {
      if (item is! Map || item['seat'] is! int || item['user_id'] is! String) {
        throw const VoiceConnectionException('Invalid seat server response.');
      }
      final seat = item['seat'] as int;
      if (seat < 0 || seat >= count || occupants.containsKey(seat) || (item['user_id'] as String).isEmpty) {
        throw const VoiceConnectionException('Invalid seat server response.');
      }
      occupants[seat] = item['user_id'] as String;
    }
    if (mine != null && !occupants.containsKey(mine)) {
      throw const VoiceConnectionException('Invalid seat server response.');
    }
    return VoiceSeatState(count, mine as int?, Map.unmodifiable(occupants));
  }
}

Future<VoiceSeatState> requestVoiceSeat({
  required String roomId,
  required String? accessToken,
  required String action,
  int? seat,
  http.Client? client,
}) async {
  if (!const ['state', 'take', 'leave', 'renew'].contains(action)) {
    throw const VoiceConnectionException('Invalid seat action.');
  }
  if (accessToken == null || accessToken.isEmpty) {
    throw const VoiceConnectionException('Sign in to use room seats.');
  }
  final transport = client ?? http.Client();
  try {
    final result = await transport.post(Uri.parse(voiceTokenEndpoint),
      headers: {'Authorization': 'Bearer $accessToken', 'Content-Type': 'application/json'},
      body: jsonEncode({'room_id': roomId, 'action': action, if(seat != null) 'seat': seat}),
    ).timeout(const Duration(seconds: 15));
    if (result.statusCode == 409) {
      throw const VoiceConnectionException('Seat occupied or expired. Please try again.');
    }
    if (result.statusCode == 401) {
      throw const VoiceConnectionException('Sign in again to use room seats.');
    }
    if (result.statusCode == 403) {
      throw const VoiceConnectionException('This account or room is unavailable.');
    }
    if (result.statusCode != 200) {
      throw const VoiceConnectionException('Seat server unavailable. Please retry.');
    }
    return VoiceSeatState.parse(jsonDecode(result.body));
  } on VoiceConnectionException {
    rethrow;
  } catch (_) {
    throw const VoiceConnectionException('Could not update your seat. Please retry.');
  } finally {
    if (client == null) transport.close();
  }
}

