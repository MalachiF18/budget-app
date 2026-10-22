import 'dart:convert';

import 'package:budget_app/features/group/group_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const receiver = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const payer = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  late SupabaseClient client;
  late List<http.Request> requests;
  late bool fail;
  setUp(() async {
    requests = [];
    fail = false;
    client = SupabaseClient(
      'https://budget.example',
      'publishable-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          fail
              ? '{"message":"permission denied","code":"42501"}'
              : '"payment-id"',
          fail ? 403 : 200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'sub': receiver, 'exp': 4102444800})))
        .replaceAll('=', '');
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
        'token_type': 'bearer',
        'refresh_token': 'test-refresh',
        'user': {
          'id': receiver,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-10-22T00:00:00Z',
        },
      }),
    );
  });
  tearDown(() async => client.dispose());
  test(
    'calls existing receiver-only RPC; receiver cannot be supplied by client',
    () async {
      await SupabaseGroupRepository(
        client,
      ).recordReceivedPayment('group', payer, 1234, DateTime(2026, 10, 21, 18));
      expect(requests.single.url.path, '/rest/v1/rpc/record_payment');
      expect(requests.single.method, 'POST');
      expect(jsonDecode(requests.single.body), {
        'p_group_id': 'group',
        'p_from_user': payer,
        'p_amount_cents': 1234,
        'p_occurred_on': '2026-10-21',
      });
    },
  );
  test('payer cannot record own outbound payment and invalid amounts never reach server', () async {
    final repo = SupabaseGroupRepository(client);
    await expectLater(
      repo.recordReceivedPayment(
        'group',
        receiver,
        1200,
        DateTime(2026, 10, 22),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repo.recordReceivedPayment('group', payer, 0, DateTime(2026, 10, 22)),
      throwsArgumentError,
    );
    await expectLater(
      repo.recordReceivedPayment('group', payer, -1, DateTime(2026, 10, 22)),
      throwsArgumentError,
    );
    expect(requests, isEmpty);
  });
  test(
    'database permission denial is propagated instead of marking paid',
    () async {
      fail = true;
      await expectLater(
        SupabaseGroupRepository(
          client,
        ).recordReceivedPayment('group', payer, 1200, DateTime(2026, 10, 22)),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
    },
  );
}
