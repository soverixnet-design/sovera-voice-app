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
