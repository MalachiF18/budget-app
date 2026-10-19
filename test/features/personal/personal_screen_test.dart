import 'package:budget_app/features/personal/budget.dart';
import 'package:budget_app/features/personal/budget_repository.dart';
import 'package:budget_app/features/personal/personal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBudgetRepository implements BudgetRepository {
  PersonalBudget value = PersonalBudget(earnings: 10000);
  bool fail = false;
  @override
  Future<PersonalBudget> load(DateTime month) async => value;
  @override
  Future<void> save(PersonalBudget budget, DateTime month) async {
    if (fail) throw Exception('offline');
    value = budget;
  }

  @override
  Future<void> addTransaction(Spending spending) async {
    value = value.copyWith(transactions: [...value.transactions, spending]);
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeBudgetRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalScreen(
          repository: repo,
          now: () => DateTime(2026, 10, 19),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'W M Y order, monthly default; earnings sheet saves and survives reopen',
    (tester) async {
      final repo = FakeBudgetRepository();
      await open(tester, repo);
      final toggle = tester.widget<SegmentedButton<BudgetPeriod>>(
        find.byType(SegmentedButton<BudgetPeriod>),
      );
      expect(toggle.segments.map((s) => s.value), BudgetPeriod.values);
      expect(toggle.selected, {BudgetPeriod.month});
      await tester.tap(find.text('Your earnings'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('amount')), '250');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.value.spendingMoney, 25000);
      await tester.pumpWidget(const SizedBox());
      await open(tester, repo);
      expect(find.text('\$250.00'), findsWidgets);
    },
  );
  testWidgets('savings changes WELL to red bold BAD', (tester) async {
    final repo = FakeBudgetRepository();
    await open(tester, repo);
    expect(
      tester.widget<Text>(find.text("You're doing WELL")).style!.color,
      Colors.green,
    );
    await tester.tap(find.text('Savings target'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '200');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final status = tester.widget<Text>(find.text("You're doing BAD"));
    expect(status.style!.color, Colors.red);
    expect(status.style!.fontWeight, FontWeight.bold);
    expect(repo.value.spendingMoney, -10000);
  });
  testWidgets('each list card opens a sheet and adds an item', (tester) async {
    final repo = FakeBudgetRepository();
    await open(tester, repo);
    for (final label in [
      'Necessary bills',
      'Subscriptions',
      'One-time needs',
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add item'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('description')), 'Example');
      await tester.enterText(find.byKey(const Key('amount')), '10');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }
    expect(repo.value.items.length, 3);
    expect(repo.value.spendingMoney, 7000);
  });
  testWidgets('transaction defaults today and reduces spending money', (
    tester,
  ) async {
    final repo = FakeBudgetRepository();
    await open(tester, repo);
    await tester.scrollUntilVisible(find.text('Add transaction'), 300);
    await tester.tap(find.text('Add transaction'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-19'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('description')), 'Lunch');
    await tester.enterText(find.byKey(const Key('amount')), '12.34');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.value.spendingMoney, 8766);
    expect(repo.value.transactions.single.date, DateTime(2026, 10, 19));
    await tester.scrollUntilVisible(find.text('Lunch'), 200);
    expect(find.text('Lunch'), findsOneWidget);
  });
  testWidgets('failed save keeps sheet open without changing budget', (
    tester,
  ) async {
    final repo = FakeBudgetRepository()..fail = true;
    await open(tester, repo);
    await tester.tap(find.text('Your earnings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '200');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save. Please try again.'), findsOneWidget);
    expect(repo.value.earnings, 10000);
  });
  testWidgets(
    'percent switch saves; period taps change displayed projections',
    (tester) async {
      final repo = FakeBudgetRepository();
      await open(tester, repo);
      await tester.tap(find.text('Savings target'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('% after bills'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('amount')), '25');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.value.savings, 2500);
      expect(repo.value.savingsMode, SavingsMode.percent);
      await tester.tap(find.text('Y'));
      await tester.pumpAndSettle();
      expect(find.text('\$1,200.00'), findsOneWidget);
      await tester.tap(find.text('W'));
      await tester.pumpAndSettle();
      expect(find.text('\$23.08'), findsOneWidget);
    },
  );
  testWidgets('list items can be edited and removed', (tester) async {
    final repo = FakeBudgetRepository();
    repo.value = repo.value.copyWith(
      items: [BudgetItem('Rent', 1000, ItemKind.bill)],
    );
    await open(tester, repo);
    await tester.tap(find.text('Necessary bills'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount')), '20');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.value.spendingMoney, 8000);
    await tester.tap(find.text('Necessary bills'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Rent'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.value.items, isEmpty);
    expect(repo.value.spendingMoney, 10000);
  });
  testWidgets('transaction date can be changed and spending turns BAD', (
    tester,
  ) async {
    final repo = FakeBudgetRepository();
    await open(tester, repo);
    await tester.scrollUntilVisible(find.text('Add transaction'), 300);
    await tester.tap(find.text('Add transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-10-19'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('description')), 'Groceries');
    await tester.enterText(find.byKey(const Key('amount')), '120');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.value.transactions.single.date, DateTime(2026, 10, 18));
    expect(repo.value.spendingMoney, -2000);
    await tester.scrollUntilVisible(find.text("You're doing BAD"), -300);
    expect(
      tester.widget<Text>(find.text("You're doing BAD")).style!.color,
      Colors.red,
    );
  });
}
