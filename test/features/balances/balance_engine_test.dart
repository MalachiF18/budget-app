import 'package:budget_app/features/balances/balance_engine.dart';
import 'package:budget_app/features/group/group_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget_app/features/balances/example_ledger.dart';

void main() {
  final now = DateTime(2026, 10, 22, 15);
  test('10 dollars / 3 = 3.34 + 3.33 + 3.33', () {
    expect(splitAmount(1000, 3), [334, 333, 333]);
  });
  test('shares always sum exactly; difference at most one cent', () {
    for (var amount = 0; amount < 10000; amount += 17) {
      for (var people = 1; people <= 20; people++) {
        final shares = splitAmount(amount, people);
        expect(shares.fold<int>(0, (a, b) => a + b), amount);
        expect(shares.first - shares.last, inInclusiveRange(0, 1));
      }
    }
    expect(splitAmount(2, 4), [1, 1, 0, 0]);
    expect(() => splitAmount(1, 0), throwsArgumentError);
    expect(() => splitAmount(-1, 2), throwsArgumentError);
  });
  test('mockup totals and pairwise amounts match exactly', () {
    final group = exampleLedger(now);
    final engine = BalanceEngine(group);
    expect(engine.totalSpent, 13200);
    expect(engine.spentBy('you'), 3000);
    expect(engine.spentBy('malachi'), 4800);
    expect(engine.spentBy('davante'), 0);
    expect(engine.spentBy('jordan'), 5400);
    expect(engine.between('you', 'malachi').youOwe, 1200);
    expect(engine.between('you', 'jordan').youOwe, 1800);
    expect(engine.between('you', 'davante').theyOwe, 3000);
    expect(engine.between('you', 'malachi').theyOwe, 0);
    expect(engine.between('you', 'you').youOwe, 0);
  });
  test('payment reduces debt; opposite expenses net only within each pair', () {
    final group = GroupLedger(
      const [],
      [
        GroupExpense(
          id: '1',
          paidBy: 'a',
          createdBy: 'a',
          description: 'Dinner',
          amount: 1000,
          shares: {'a': 334, 'b': 333, 'c': 333},
          date: now,
        ),
        GroupExpense(
          id: '2',
          paidBy: 'b',
          createdBy: 'b',
          description: 'Taxi',
          amount: 100,
          shares: {'a': 100},
          date: now,
        ),
      ],
      [GroupPayment('b', 'a', 200, now)],
    );
    final engine = BalanceEngine(group);
    expect(engine.between('b', 'a').youOwe, 33);
    expect(engine.between('a', 'b').theyOwe, 33);
    expect(engine.between('c', 'a').youOwe, 333);
    expect(engine.between('b', 'c').youOwe, 0);
  });
  test('exact payment clears balance; overpayment becomes credit', () {
    final group = exampleLedger(now);
    final settled = group.withPayment(
      GroupPayment('davante', 'you', 3000, now),
    );
    expect(BalanceEngine(settled).between('you', 'davante').theyOwe, 0);
    final credit = settled.withPayment(GroupPayment('davante', 'you', 1, now));
    expect(BalanceEngine(credit).between('you', 'davante').youOwe, 1);
  });
  test(
    'W and M are inclusive rolling 7 and 30 calendar days; ALL is unfiltered',
    () {
      expect(ActivityPeriod.week.includes(DateTime(2026, 10, 16), now), isTrue);
      expect(
        ActivityPeriod.week.includes(DateTime(2026, 10, 15, 23, 59), now),
        isFalse,
      );
      expect(ActivityPeriod.month.includes(DateTime(2026, 9, 23), now), isTrue);
      expect(
        ActivityPeriod.month.includes(DateTime(2026, 9, 22), now),
        isFalse,
      );
      expect(
        ActivityPeriod.month.includes(DateTime(2026, 10, 23), now),
        isFalse,
      );
      expect(ActivityPeriod.all.includes(DateTime(2020), now), isTrue);
      expect(
        ActivityPeriod.week.includes(DateTime(2026, 10, 22, 23), now),
        isTrue,
      );
    },
  );
  test(
    'filters both expenses and payments and sorts a mixed ledger newest first',
    () {
      final group = exampleLedger(now).withPayment(
        GroupPayment('davante', 'you', 1000, DateTime(2026, 10, 21)),
      );
      final week = GroupActivity(group, ActivityPeriod.week, now);
      final month = GroupActivity(group, ActivityPeriod.month, now);
      final all = GroupActivity(group, ActivityPeriod.all, now);
      expect(week.totalSpent, 3000);
      expect(month.totalSpent, 7800);
      expect(all.totalSpent, 13200);
      expect(week.ledgerFor('you').map((e) => e.isPayment), [false, true]);
      expect(week.ledgerFor('malachi'), isEmpty);
      expect(all.ledgerFor('davante').last.amount, 1000);
    },
  );
  test('pair symmetry and group debt conservation', () {
    final ledger = exampleLedger(now)
        .withPayment(GroupPayment('davante', 'you', 1200, now));
    final engine = BalanceEngine(ledger);
    var owes = 0, owed = 0;
    for (final member in ledger.members) {
      final totals = engine.totalsFor(member.id);
      owes += totals.youOwe;
      owed += totals.theyOwe;
      for (final other in ledger.members) {
        expect(
          engine.between(member.id, other.id).youOwe,
          engine.between(other.id, member.id).theyOwe,
        );
      }
    }
    expect(owes, owed);
  });
  test(
    'rolling windows cross month, year and DST boundaries by calendar date',
    () {
      expect(
        ActivityPeriod.week.includes(
          DateTime(2025, 12, 28),
          DateTime(2026, 1, 3),
        ),
        isTrue,
      );
      expect(
        ActivityPeriod.week.includes(
          DateTime(2025, 12, 27),
          DateTime(2026, 1, 3),
        ),
        isFalse,
      );
      expect(
        ActivityPeriod.month.includes(
          DateTime(2024, 2, 1),
          DateTime(2024, 3, 1),
        ),
        isTrue,
      );
      expect(
        ActivityPeriod.week.includes(
          DateTime(2026, 10, 27),
          DateTime(2026, 11, 2),
        ),
        isTrue,
      );
    },
  );
}
