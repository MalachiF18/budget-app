import '../group/group_models.dart';
export 'split_math.dart';

/// W/M mean the last 7/30 local calendar days, including today. ALL is unfiltered.
/// Use calendar constructors rather than Duration subtraction across DST changes.
enum ActivityPeriod {
  week('W', 7),
  month('M', 30),
  all('ALL', null);

  const ActivityPeriod(this.label, this.days);
  final String label;
  final int? days;
  String get description => days == null ? 'All time' : 'Last $days days';
  bool includes(DateTime date, DateTime now) {
    if (days == null) return true;
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(now.year, now.month, now.day - days! + 1);
    final end = DateTime(now.year, now.month, now.day + 1);
    return !day.isBefore(start) && day.isBefore(end);
  }
}

class PairBalance {
  const PairBalance(this.youOwe, this.theyOwe);
  final int youOwe, theyOwe;
}

/// Pairwise net debt; never moves debts between unrelated members. The payer's
/// own expense share creates no debt. Payments reduce from -> to obligations.
/// Overpayments become credit, rather than silently disappearing.
class BalanceEngine {
  BalanceEngine(this.ledger) {
    for (final expense in ledger.expenses) {
      if (expense.amount <= 0 ||
          expense.shares.values.any((s) => s < 0) ||
          expense.shares.values.fold<int>(0, (sum, s) => sum + s) !=
              expense.amount) {
        throw ArgumentError(
          'Expense shares must add up to its positive amount.',
        );
      }
      for (final share in expense.shares.entries) {
        if (share.key != expense.paidBy) {
          _add(share.key, expense.paidBy, share.value);
        }
      }
    }
    for (final payment in ledger.payments) {
      if (payment.amount <= 0 || payment.from == payment.to) {
        throw ArgumentError(
          'A payment needs two people and a positive amount.',
        );
      }
      _add(payment.from, payment.to, -payment.amount);
    }
  }
  final GroupLedger ledger;
  final Map<String, Map<String, int>> _debts = {};
  void _add(String from, String to, int amount) {
    final row = _debts.putIfAbsent(from, () => {});
    row[to] = (row[to] ?? 0) + amount;
  }

  int get totalSpent => ledger.expenses.fold(0, (sum, e) => sum + e.amount);
  int spentBy(String id) => ledger.expenses
      .where((e) => e.paidBy == id)
      .fold(0, (sum, e) => sum + e.amount);
  PairBalance between(String viewer, String other) {
    if (viewer == other) return const PairBalance(0, 0);
    final net = (_debts[viewer]?[other] ?? 0) - (_debts[other]?[viewer] ?? 0);
    return PairBalance(net > 0 ? net : 0, net < 0 ? -net : 0);
  }

  PairBalance totalsFor(String viewer) {
    final others = {..._debts.keys, ..._debts.values.expand((r) => r.keys)}
      ..remove(viewer);
    var owe = 0, owed = 0;
    for (final other in others) {
      final pair = between(viewer, other);
      owe += pair.youOwe;
      owed += pair.theyOwe;
    }
    return PairBalance(owe, owed);
  }
}

class LedgerEntry {
  const LedgerEntry.expense(GroupExpense value)
    : expense = value,
      payment = null;
  const LedgerEntry.payment(GroupPayment value)
    : expense = null,
      payment = value;
  final GroupExpense? expense;
  final GroupPayment? payment;
  bool get isPayment => payment != null;
  DateTime get date => expense?.date ?? payment!.date;
  int get amount => expense?.amount ?? payment!.amount;
}

/// Activity filtering does not change outstanding all-time debts. Otherwise a
/// payment in this week for an older expense would look like a new reverse debt.
class GroupActivity {
  GroupActivity(GroupLedger ledger, ActivityPeriod period, DateTime now)
    : expenses = ledger.expenses
          .where((e) => period.includes(e.date, now))
          .toList(),
      payments = ledger.payments
          .where((p) => period.includes(p.date, now))
          .toList();
  final List<GroupExpense> expenses;
  final List<GroupPayment> payments;
  int get totalSpent => expenses.fold(0, (sum, e) => sum + e.amount);
  int spentBy(String id) =>
      expenses.where((e) => e.paidBy == id).fold(0, (sum, e) => sum + e.amount);
  List<LedgerEntry> ledgerFor([String? member]) {
    final entries = <LedgerEntry>[
      for (final e in expenses)
        if (member == null ||
            e.paidBy == member ||
            e.shares.containsKey(member))
          LedgerEntry.expense(e),
      for (final p in payments)
        if (member == null || p.from == member || p.to == member)
          LedgerEntry.payment(p),
    ];
    // Stable ties: expenses precede payments; input order breaks other ties.
    final indexed = entries.indexed.toList()
      ..sort((a, b) {
        final order = b.$2.date.compareTo(a.$2.date);
        return order == 0 ? a.$1.compareTo(b.$1) : order;
      });
    return indexed.map((e) => e.$2).toList();
  }
}
