import 'dart:async';
import 'dart:typed_data';

import '../core/auth/auth_repository.dart';
import '../features/balances/example_ledger.dart';
import '../features/group/group_models.dart';
import '../features/group/group_repository.dart';
import '../features/personal/budget.dart' as personal;
import '../features/personal/budget_repository.dart';

/// Explicit, isolated in-memory demo. No auth session, database or network calls.
class DemoAuthRepository implements AuthRepository {
  @override
  Future<String> ensureSignedIn() async => 'you';
  @override
  Future<String?> loadDisplayName(String userId) async => 'You';
  @override
  Future<void> saveDisplayName(String userId, String name) async {}
}

class DemoBudgetRepository implements BudgetRepository {
  personal.PersonalBudget _budget = personal.PersonalBudget.example();
  @override
  Future<personal.PersonalBudget> load(DateTime month) async => _budget;
  @override
  Future<void> save(personal.PersonalBudget budget, DateTime month) async =>
      _budget = budget;
  @override
  Future<void> addTransaction(personal.Spending spending) async {
    _budget = _budget.copyWith(
      transactions: [..._budget.transactions, spending],
    );
  }
}

class DemoGroupRepository implements GroupRepository {
  DemoGroupRepository({DateTime? now}) {
    _ledgers['demo'] = exampleLedger(now ?? DateTime.now());
  }
  final _events = StreamController<void>.broadcast();
  final _groups = [const SpendingGroup('demo', 'Housemates', 'K7Q4ZPABC234')];
  final Map<String, GroupLedger> _ledgers = {};
  final Map<String, Uint8List> _photos = {};
  int _serial = 0;
  @override
  String get userId => 'you';
  @override
  Future<List<SpendingGroup>> groups() async => List.of(_groups);
  @override
  Future<GroupLedger> load(String groupId) async => _ledgers[groupId]!;
  @override
  Stream<void> changes(String groupId) => _events.stream;
  @override
  Future<String> create(String name) async {
    final id = 'demo-${++_serial}';
    _groups.add(
      SpendingGroup(id, name, 'DEMO${_serial.toString().padLeft(8, '0')}'),
    );
    _ledgers[id] = const GroupLedger([GroupMember('you', 'You')], [], []);
    return id;
  }

  @override
  Future<String?> join(String code) async {
    final normalized = code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    for (final group in _groups) {
      if (group.code == normalized) return group.id;
    }
    return null;
  }

  @override
  Future<void> save(String groupId, GroupExpense expense) async {
    if (expense.createdBy != userId) {
      throw StateError('Only the creator can edit.');
    }
    final ledger = _ledgers[groupId]!;
    _ledgers[groupId] = GroupLedger(ledger.members, [
      ...ledger.expenses.where((e) => e.id != expense.id),
      GroupExpense(
        id: expense.id.isEmpty ? 'demo-expense-${++_serial}' : expense.id,
        description: expense.description,
        amount: expense.amount,
        date: expense.date,
        paidBy: expense.paidBy,
        createdBy: expense.createdBy,
        shares: Map.of(expense.shares),
        receiptPath: expense.receiptPath,
      ),
    ], ledger.payments);
    _events.add(null);
  }

  @override
  Future<void> delete(GroupExpense expense) async {
    if (expense.createdBy != userId) {
      throw StateError('Only the creator can delete.');
    }
    for (final entry in _ledgers.entries.toList()) {
      _ledgers[entry.key] = GroupLedger(
        entry.value.members,
        entry.value.expenses.where((e) => e.id != expense.id).toList(),
        entry.value.payments,
      );
    }
    _events.add(null);
  }

  @override
  Future<void> recordReceivedPayment(
    String groupId,
    String fromUserId,
    int amountCents,
    DateTime date,
  ) async {
    final ledger = _ledgers[groupId]!;
    if (fromUserId == userId ||
        amountCents <= 0 ||
        !ledger.members.any((m) => m.id == fromUserId)) {
      throw ArgumentError('Record money received from another member.');
    }
    _ledgers[groupId] = ledger.withPayment(
      GroupPayment(fromUserId, userId, amountCents, date),
    );
    _events.add(null);
  }

  @override
  Future<String> upload(String groupId, Uint8List bytes) async {
    final path = '$groupId/demo-photo-${++_serial}';
    _photos[path] = Uint8List.fromList(bytes);
    return path;
  }

  @override
  Future<void> removeReceipt(String path) async => _photos.remove(path);
  @override
  Future<Uint8List> receipt(String path) async => _photos[path]!;
  Future<void> dispose() => _events.close();
}
