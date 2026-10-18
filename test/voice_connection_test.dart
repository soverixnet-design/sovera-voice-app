import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sovera/voice_connection.dart';

void main() {
  test('Signed out users never send a request', () async {
    var requested = false;
    final client = MockClient((_) async {
      requested = true;
      return http.Response('{}', 200);
    });
    await expectLater(requestVoiceCredentials(roomId: 'room', accessToken: null, client: client), throwsA(isA<VoiceConnectionException>()));
    expect(requested, isFalse);
  });
  test('Session is sent only to the fixed token endpoint with room ID', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), voiceTokenEndpoint);
      expect(request.headers['Authorization'], 'Bearer session-fixture');
      expect(jsonDecode(request.body), {'room_id': 'room-fixture'});
      return http.Response(jsonEncode({'url': voiceServerUrl, 'token': 'room-token-fixture'}), 200);
    });
    final result = await requestVoiceCredentials(roomId: 'room-fixture', accessToken: 'session-fixture', client: client);
    expect(result.token, 'room-token-fixture');
    expect(result.url, voiceServerUrl);
  });
  test('Untrusted URLs and malformed credentials are rejected', () async {
    for (final body in [
      {'url': 'wss://other.example', 'token': 'secret-fixture'},
      {'url': voiceServerUrl, 'token': ''},
      {'url': voiceServerUrl},
    ]) {
      await expectLater(requestVoiceCredentials(roomId: 'room', accessToken: 'session', client: MockClient((_) async => http.Response(jsonEncode(body), 200))), throwsA(isA<VoiceConnectionException>()));
    }
  });
  test('Server bodies and tokens are never exposed in errors', () async {
    for (final status in [401, 403, 429, 500]) {
      try {
        await requestVoiceCredentials(roomId: 'room', accessToken: 'session', client: MockClient((_) async => http.Response('secret-fixture', status)));
        fail('Expected failure');
      } on VoiceConnectionException catch (error) {
        expect(error.message, isNot(contains('secret-fixture')));
      }
    }
  });

  test('Seat operations send server actions and parse authoritative occupancy', () async {
    final client = MockClient((request) async {
      expect(jsonDecode(request.body), {'room_id': 'room', 'action': 'take', 'seat': 2});
      expect(request.headers['Authorization'], 'Bearer session');
      return http.Response(jsonEncode({'seat_count': 5, 'my_seat': 2,
        'seats': [{'seat': 2, 'user_id': 'alice'}]}), 200);
    });
    final result = await requestVoiceSeat(roomId: 'room', accessToken: 'session', action: 'take', seat: 2, client: client);
    expect(result.mine, 2);
    expect(result.occupants, {2: 'alice'});
  });
  test('Seat collision fails instead of applying a local seat', () async {
    await expectLater(requestVoiceSeat(roomId: 'room', accessToken: 'session', action: 'take', seat: 0,
      client: MockClient((_) async => http.Response('private-response', 409))),
      throwsA(isA<VoiceConnectionException>().having((e) => e.message, 'message', contains('occupied'))));
  });
  test('Invalid and duplicate seat assignments are rejected', () {
    for(final data in [
      {'seat_count': 0, 'seats': []},
      {'seat_count': 5, 'my_seat': 7, 'seats': []},
      {'seat_count': 5, 'my_seat': 0, 'seats': []},
      {'seat_count': 5, 'seats': [{'seat': 0, 'user_id': 'a'}, {'seat': 0, 'user_id': 'b'}]},
      {'seat_count': 5, 'seats': [{'seat': -1, 'user_id': 'a'}]},
    ]) {
      expect(() => VoiceSeatState.parse(data), throwsA(isA<VoiceConnectionException>()));
    }
  });
}
