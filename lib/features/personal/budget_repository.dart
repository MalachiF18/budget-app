import 'package:supabase_flutter/supabase_flutter.dart';

import 'budget.dart';

abstract interface class BudgetRepository {
  Future<PersonalBudget> load(DateTime month);
  Future<void> save(PersonalBudget budget, DateTime month);
  Future<void> addTransaction(Spending spending);
}

class SupabaseBudgetRepository implements BudgetRepository {
  SupabaseBudgetRepository(this.client);
  final SupabaseClient client;
  String get userId =>
      client.auth.currentUser?.id ?? (throw StateError('Sign in first'));

  @override
  Future<PersonalBudget> load(DateTime month) async {
    final owner = userId;
    final start = dateOnly(DateTime(month.year, month.month));
    final end = dateOnly(DateTime(month.year, month.month + 1));
    final row = await client
        .from('budgets')
        .select()
        .eq('user_id', owner)
        .maybeSingle();
    final items = row == null
        ? <Map<String, dynamic>>[]
        : await client
              .from('budget_items')
              .select()
              .eq('budget_id', row['id'] as String);
    final transactions = await client
        .from('transactions')
        .select()
        .eq('user_id', owner)
        .gte('occurred_on', start)
        .lt('occurred_on', end)
        .order('occurred_on', ascending: false)
        .order('created_at', ascending: false);
    return PersonalBudget(
      earnings: (row?['earnings_cents'] as num?)?.toInt() ?? 0,
      savingsMode: row?['savings_mode'] == 'percent'
          ? SavingsMode.percent
          : SavingsMode.fixed,
      savingsValue: (row?['savings_value'] as num?)?.toInt() ?? 0,
      items: items
          .where((i) => i['kind'] != 'one_time' || i['month'] == start)
          .map(
            (i) => BudgetItem(
              i['name'] as String,
              (i['amount_cents'] as num).toInt(),
              ItemKind.values.firstWhere((k) => k.databaseValue == i['kind']),
            ),
          )
          .toList(),
      transactions: transactions
          .map(
            (t) => Spending(
              t['description'] as String,
              (t['amount_cents'] as num).toInt(),
              DateTime.parse(t['occurred_on'] as String),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> save(PersonalBudget budget, DateTime month) async {
    userId; // Require a session; ownership is derived again inside the RPC.
    await client.rpc(
      'save_personal_budget',
      params: {
        'p_earnings': budget.earnings,
        'p_savings_mode': budget.savingsMode.name,
        'p_savings_value': budget.savingsValue,
        'p_month': dateOnly(DateTime(month.year, month.month)),
        'p_items': budget.items
            .map(
              (i) => {
                'name': i.name,
                'amount_cents': i.amount,
                'kind': i.kind.databaseValue,
              },
            )
            .toList(),
      },
    );
  }

  @override
  Future<void> addTransaction(Spending spending) async {
    await client.from('transactions').insert({
      'user_id': userId,
      'description': spending.description,
      'amount_cents': spending.amount,
      'occurred_on': dateOnly(spending.date),
    });
  }
}
