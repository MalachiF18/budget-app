import 'package:budget_app/core/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

// Primary color of the theme currently applied to the shell's Scaffold.
Color _primary(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary;

void main() {
  testWidgets('starts on Personal', (tester) async {
    await tester.pumpWidget(
      BudgetApp(auth: FakeAuthRepository(displayName: 'Sam')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personal'), findsWidgets);
    expect(find.textContaining('card 2.3'), findsOneWidget);
  });

  testWidgets('tapping Group shows the Group screen', (tester) async {
    await tester.pumpWidget(
      BudgetApp(auth: FakeAuthRepository(displayName: 'Sam')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Group'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('card 3.2'), findsOneWidget);
  });

  testWidgets('primary color differs between tabs', (tester) async {
    await tester.pumpWidget(
      BudgetApp(auth: FakeAuthRepository(displayName: 'Sam')),
    );
    await tester.pumpAndSettle();
    final personal = _primary(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Group'),
      ),
    );
    await tester.pumpAndSettle();
    final group = _primary(tester);

    expect(group, isNot(personal));
  });
}
