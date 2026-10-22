import 'dart:async';
import 'dart:convert';

import 'package:budget_app/features/group/group_models.dart';
import 'package:budget_app/features/group/group_repository.dart';
import 'package:budget_app/features/group/group_screen.dart';
import 'package:budget_app/features/group/expense_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGroups implements GroupRepository {
  FakeGroups() {
    addTearDown(events.close);
  }
  @override
  String get userId => 'me';
  List<SpendingGroup> items = [
    const SpendingGroup('group', 'Housemates', 'ABCDEFGH2345'),
  ];
  final events = StreamController<void>.broadcast();
  final members = [
    const GroupMember('me', 'Davante'),
    const GroupMember('allen', 'Allen'),
    const GroupMember('malachi', 'Malachi'),
  ];
  List<GroupExpense> expenses = [];
  GroupExpense? saved;
  String? joined;
  String? viewed;
  @override
  Future<List<SpendingGroup>> groups() async => items;
  @override
  Future<String> create(String name) async {
    items = [SpendingGroup('new', name, 'COPY23456789')];
    return 'new';
  }

  @override
  Future<String?> join(String code) async {
    joined = code;
    if (code == 'bad') return null;
    items = [const SpendingGroup('joined', 'Joined group', 'ABCDEFGH2345')];
    return 'joined';
  }

  @override
  Future<GroupLedger> load(String groupId) async =>
      GroupLedger(members, expenses, []);
  @override
  Stream<void> changes(String groupId) => events.stream;
  @override
  Future<void> save(String groupId, GroupExpense expense) async {
    saved = expense;
  }

  @override
  Future<void> delete(GroupExpense expense) async {
    expenses.remove(expense);
  }

  @override
  Future<String> upload(String groupId, Uint8List bytes) async =>
      '$groupId/receipt.jpg';
  @override
  Future<void> removeReceipt(String path) async {}
  @override
  Future<Uint8List> receipt(String path) async {
    viewed = path;
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=',
    );
  }
}

GroupExpense expense(
  String id,
  String payer, {
  String? creator,
  String? receipt,
}) => GroupExpense(
  id: id,
  description: id,
  amount: 1001,
  date: DateTime(2026, 1, 1),
  paidBy: payer,
  createdBy: creator ?? payer,
  shares: const {'me': 501, 'allen': 500},
  receiptPath: receipt,
);
Future<void> form(WidgetTester tester, FakeGroups repo) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ExpenseForm(
        repository: repo,
        groupId: 'group',
        members: repo.members,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> screen(WidgetTester tester, FakeGroups repo) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: GroupScreen(repository: repo)));
  await tester.pumpAndSettle();
}

void main() {
  test('splits exact cents deterministically and supports direct charge', () {
    expect(splitCents(1001, ['b', 'a', 'a']), {'a': 501, 'b': 500});
    expect(splitCents(1001, ['b']), {'b': 1001});
    expect(() => splitCents(100, []), throwsArgumentError);
  });
  testWidgets('defaults and select / deselect all', (tester) async {
    final repo = FakeGroups();
    await form(tester, repo);
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((w) => w.value == false),
      isTrue,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(find.text(dateOnly(DateTime.now())), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((w) => w.value == true),
      isTrue,
    );
    await tester.tap(find.text('Deselect all'));
    await tester.pump();
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((w) => w.value == false),
      isTrue,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });
  testWidgets('share off and one member saves a direct charge', (tester) async {
    final repo = FakeGroups();
    await form(tester, repo);
    await tester.enterText(find.byType(TextFormField).at(0), 'Lunch');
    await tester.enterText(find.byType(TextFormField).at(1), '12.35');
    await tester.tap(find.byKey(const ValueKey('charge-allen')));
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.ensureVisible(find.text('Save expense'));
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(repo.saved!.shares, {'allen': 1235});
  });
  testWidgets('empty charge with share off is rejected', (tester) async {
    final repo = FakeGroups();
    await form(tester, repo);
    await tester.enterText(find.byType(TextFormField).at(0), 'Lunch');
    await tester.enterText(find.byType(TextFormField).at(1), '12.35');
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.ensureVisible(find.text('Save expense'));
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(repo.saved, isNull);
    expect(find.textContaining('Choose someone'), findsOneWidget);
  });
  testWidgets('create displays a copyable sync code', (tester) async {
    final repo = FakeGroups()..items = [];
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await screen(tester, repo);
    await tester.tap(find.widgetWithText(FilledButton, 'Create group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Trip');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('COPY23456789'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy sync code'));
    await tester.pump();
    expect(copied, 'COPY23456789');
  });
  testWidgets('joining by code opens group with ALL selected', (tester) async {
    final repo = FakeGroups()..items = [];
    await screen(tester, repo);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Join group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ABCD-EFGH-2345');
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();
    expect(repo.joined, 'ABCD-EFGH-2345');
    expect(find.text('Joined group'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      {'ALL'},
    );
  });
  testWidgets('member ledger filters payer and hides edit/delete for others', (
    tester,
  ) async {
    final repo = FakeGroups()
      ..expenses = [
        expense('My lunch', 'me'),
        expense('Their lunch', 'allen'),
        expense('Other payer', 'malachi', creator: 'me'),
      ];
    await screen(tester, repo);
    await tester.tap(find.text('Allen'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Their lunch'), 250);
    expect(find.text('My lunch'), findsNothing);
    expect(find.text('Other payer'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    await tester.ensureVisible(find.text('Show all'));
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    // Ownership follows created_by, not paid_by.
    expect(find.text('Edit'), findsNWidgets(2));
    expect(find.text('Delete'), findsNWidgets(2));
  });
  testWidgets('Realtime event refetches ledger without refresh gesture', (
    tester,
  ) async {
    final repo = FakeGroups();
    await screen(tester, repo);
    repo.expenses = [expense('Remote expense', 'allen')];
    repo.events.add(null);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Remote expense'), 250);
    expect(find.text('Remote expense'), findsOneWidget);
    repo.expenses = [];
    repo.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Remote expense'), findsNothing);
  });
  testWidgets('receipt icon opens the private photo viewer', (tester) async {
    final repo = FakeGroups()
      ..expenses = [
        expense('Receipt lunch', 'allen', receipt: 'group/photo.jpg'),
      ];
    await screen(tester, repo);
    await tester.ensureVisible(find.byTooltip('View receipt'));
    await tester.tap(find.byTooltip('View receipt'));
    await tester.pumpAndSettle();
    expect(repo.viewed, 'group/photo.jpg');
    expect(find.text('Receipt'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
  testWidgets('invalid join code stays in dialog with an error', (
    tester,
  ) async {
    final repo = FakeGroups()..items = [];
    await screen(tester, repo);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Join group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();
    expect(find.text('No group found. Check the sync code.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
