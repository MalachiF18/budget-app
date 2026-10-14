import 'package:budget_app/core/auth/name_screen.dart';
import 'package:budget_app/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> saved;

  Future<void> pumpScreen(WidgetTester tester) async {
    saved = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: personalTheme,
        home: NameScreen(onSave: (name) async => saved.add(name)),
      ),
    );
  }

  Future<void> submit(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  testWidgets('empty name is rejected', (tester) async {
    await pumpScreen(tester);
    await submit(tester, '');

    expect(find.text('Enter a name'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('whitespace-only name is rejected', (tester) async {
    await pumpScreen(tester);
    await submit(tester, '    ');

    expect(find.text('Enter a name'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('41 characters is rejected', (tester) async {
    await pumpScreen(tester);
    await submit(tester, 'a' * 41);

    expect(find.text('Max 40 characters'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('40 characters is accepted', (tester) async {
    await pumpScreen(tester);
    await submit(tester, 'a' * 40);

    expect(saved, ['a' * 40]);
  });

  testWidgets('valid name is saved trimmed', (tester) async {
    await pumpScreen(tester);
    await submit(tester, '  Sam  ');

    expect(saved, ['Sam']);
  });
}
