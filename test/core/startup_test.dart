import 'package:budget_app/core/app.dart';
import 'package:budget_app/core/auth/name_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';

void main() {
  testWidgets('shows a spinner while signing in', (tester) async {
    await tester.pumpWidget(BudgetApp(auth: FakeAuthRepository()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('no display name shows NameScreen, then the tabs', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await tester.pumpWidget(BudgetApp(auth: repo));
    await tester.pumpAndSettle();

    expect(find.byType(NameScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.enterText(find.byType(TextField), ' Sam ');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(repo.saved, ['Sam']);
    expect(find.byType(NameScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('existing display name goes straight to the tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      BudgetApp(auth: FakeAuthRepository(displayName: 'Sam')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NameScreen), findsNothing);
    expect(find.text('Personal'), findsWidgets);
  });

  testWidgets('sign-in failure shows Retry; retry succeeding proceeds', (
    tester,
  ) async {
    final repo = FakeAuthRepository(displayName: 'Sam', signInFailures: 1);
    await tester.pumpWidget(BudgetApp(auth: repo));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(repo.signInCalls, 2);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
