import 'package:budget_app/demo/demo_repositories.dart';
import 'package:budget_app/features/balances/balance_engine.dart';
import 'package:budget_app/features/group/group_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingPayments extends DemoGroupRepository {
  FailingPayments() : super(now: DateTime(2026, 10, 22));
  @override
  Future<void> recordReceivedPayment(
    String groupId,
    String fromUserId,
    int amountCents,
    DateTime date,
  ) async => throw Exception('offline');
}

void main() {
  final today = DateTime(2026, 10, 22);
  Future<void> open(WidgetTester tester, DemoGroupRepository repo) async {
    addTearDown(repo.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: GroupScreen(repository: repo, now: () => today, isDemo: true),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ALL default; each card matches engine; only receiver has a button',
    (tester) async {
      final repo = DemoGroupRepository(now: today);
      await open(tester, repo);
      expect(
        tester
            .widget<SegmentedButton<String>>(
              find.byType(SegmentedButton<String>),
            )
            .selected,
        {'ALL'},
      );
      expect(find.text('\$132.00'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('owe-malachi'))).data,
        'You owe them \$12.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('owe-jordan'))).data,
        'You owe them \$18.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('owed-davante'))).data,
        'They owe you \$30.00',
      );
      expect(find.byKey(const ValueKey('receive-malachi')), findsNothing);
      expect(find.byKey(const ValueKey('receive-jordan')), findsNothing);
      expect(find.byKey(const ValueKey('receive-you')), findsNothing);
      expect(find.byKey(const ValueKey('receive-davante')), findsOneWidget);
    },
  );
  testWidgets(
    'receiver records partial payment; balance drops and member ledger includes payment',
    (tester) async {
      final repo = DemoGroupRepository(now: today);
      await open(tester, repo);
      await tester.tap(find.byKey(const ValueKey('receive-davante')));
      await tester.pumpAndSettle();
      expect(find.text('Davante paid me'), findsOneWidget);
      expect(find.text('2026-10-22'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('payment-amount')), '15');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Record received payment'),
      );
      await tester.pumpAndSettle();
      expect(
        BalanceEngine(await repo.load('demo'))
            .between('you', 'davante')
            .theyOwe,
        1500,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('owed-davante'))).data,
        'They owe you \$15.00',
      );
      await tester.tap(find.text('Davante'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Davante paid you'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('2026-10-22 • Payment received'), findsOneWidget);
      expect(find.text('\$15.00'), findsOneWidget);
      expect(find.text('Lunch for Davante'), findsOneWidget);
      expect(find.text('Groceries with Malachi'), findsNothing);
    },
  );
  testWidgets(
    'W/M change activity totals, payments and member spending, not outstanding debts',
    (tester) async {
      final repo = DemoGroupRepository(now: today);
      await repo.recordReceivedPayment(
        'demo',
        'davante',
        1000,
        DateTime(2026, 9, 1),
      );
      await open(tester, repo);
      await tester.tap(find.text('W'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('owed-davante'))).data,
        'They owe you \$20.00',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('group-total'))).data,
        '\$30.00',
      );
      await tester.scrollUntilVisible(
        find.text('Group ledger'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Davante paid you'), findsNothing);
      expect(find.text('Groceries with Malachi'), findsNothing);
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.text('M'),
        ),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.text('M'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('\$78.00'), findsOneWidget);
      await tester.tap(find.text('ALL'));
      await tester.pumpAndSettle();
      expect(find.text('\$132.00'), findsOneWidget);
    },
  );
  testWidgets('failed received payment keeps draft and original balance', (
    tester,
  ) async {
    final repo = FailingPayments();
    await open(tester, repo);
    await tester.tap(find.byKey(const ValueKey('receive-davante')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Record received payment'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not record payment. Please try again.'),
      findsOneWidget,
    );
    expect((await repo.load('demo')).payments, isEmpty);
  });
  testWidgets('zero or excessive payment is rejected before saving', (
    tester,
  ) async {
    final repo = DemoGroupRepository(now: today);
    await open(tester, repo);
    await tester.tap(find.byKey(const ValueKey('receive-davante')));
    await tester.pumpAndSettle();
    for (final amount in ['0', '30.01', '1.001']) {
      await tester.enterText(find.byKey(const Key('payment-amount')), amount);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Record received payment'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Enter an amount from \$0.01 to \$30.00.'),
        findsOneWidget,
      );
    }
    expect((await repo.load('demo')).payments, isEmpty);
  });
}
