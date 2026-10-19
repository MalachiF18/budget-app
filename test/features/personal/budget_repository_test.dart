import 'dart:convert';

import 'package:budget_app/features/personal/budget.dart';
import 'package:budget_app/features/personal/budget_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
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
        if (fail) {
          return http.Response('{"message":"offline"}', 400, request: request);
        }
        final path = request.url.path;
        Object body = [];
        if (path.endsWith('/budgets')) {
          body = {
            'id': 'budget-1',
            'earnings_cents': 100000,
            'savings_mode': 'percent',
            'savings_value': 10,
          };
        } else if (path.endsWith('/budget_items')) {
          body = [
            {
              'kind': 'bill',
              'name': 'Rent',
              'amount_cents': 40000,
              'month': null,
            },
            {
              'kind': 'one_time',
              'name': 'Current',
              'amount_cents': 1000,
              'month': '2026-10-01',
            },
            {
              'kind': 'one_time',
              'name': 'Old',
              'amount_cents': 9000,
              'month': '2026-09-01',
            },
          ];
        } else if (path.endsWith('/transactions') && request.method == 'GET') {
          body = [
            {
              'description': 'Lunch',
              'amount_cents': 1234,
              'occurred_on': '2026-10-19',
            },
          ];
        } else {
          return http.Response('', 204, request: request);
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'sub': owner, 'exp': 4102444800})))
        .replaceAll('=', '');
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
        'token_type': 'bearer',
        'refresh_token': 'test-refresh',
        'user': {
          'id': owner,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-10-19T00:00:00Z',
        },
      }),
    );
  });
  tearDown(() async => client.dispose());

  test(
    'load scopes owner/month and excludes one-time needs from other months',
    () async {
      final budget = await SupabaseBudgetRepository(client)
          .load(DateTime(2026, 10, 19));
      expect(budget.spendingMoney, 51766);
      expect(budget.items.map((i) => i.name), ['Rent', 'Current']);
      final budgets = requests.firstWhere(
        (r) => r.url.path.endsWith('/budgets'),
      );
      expect(budgets.url.queryParameters['user_id'], 'eq.$owner');
      final transactions = requests.firstWhere(
        (r) => r.url.path.endsWith('/transactions'),
      );
      expect(transactions.url.queryParameters['user_id'], 'eq.$owner');
      expect(transactions.url.queryParametersAll['occurred_on'], [
        'gte.2026-10-01',
        'lt.2026-11-01',
      ]);
    },
  );
  test(
    'save uses atomic RPC with integer cents and normalized month',
    () async {
      await SupabaseBudgetRepository(client).save(
        PersonalBudget(
          earnings: 12345,
          items: [BudgetItem('Rent', 5000, ItemKind.bill)],
        ),
        DateTime(2026, 10, 19),
      );
      final request = requests.single;
      expect(request.url.path, '/rest/v1/rpc/save_personal_budget');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['p_earnings'], 12345);
      expect(body['p_month'], '2026-10-01');
      expect(body['p_items'], [
        {'name': 'Rent', 'amount_cents': 5000, 'kind': 'bill'},
      ]);
    },
  );
  test('transaction includes owner and chosen calendar date', () async {
    await SupabaseBudgetRepository(client)
        .addTransaction(Spending('Lunch', 1234, DateTime(2026, 9, 30)));
    expect(jsonDecode(requests.single.body), {
      'user_id': owner,
      'description': 'Lunch',
      'amount_cents': 1234,
      'occurred_on': '2026-09-30',
    });
  });
  test('save propagates server failure so draft is not acknowledged', () async {
    fail = true;
    await expectLater(
      SupabaseBudgetRepository(client)
          .save(PersonalBudget(), DateTime(2026, 10)),
      throwsA(isA<PostgrestException>()),
    );
  });
  test('signed-out repository refuses requests', () async {
    final signedOut = SupabaseClient(
      'https://budget.example',
      'publishable-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await expectLater(
      SupabaseBudgetRepository(signedOut).load(DateTime(2026, 10)),
      throwsStateError,
    );
    await signedOut.dispose();
    expect(requests, isEmpty);
  });
}
