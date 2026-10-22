class SpendingGroup {
  const SpendingGroup(this.id, this.name, this.code);
  final String id, name, code;
}

class GroupMember {
  const GroupMember(this.id, this.name);
  final String id, name;
}

class GroupExpense {
  const GroupExpense({
    required this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.paidBy,
    required this.createdBy,
    required this.shares,
    this.receiptPath,
  });
  final String id, description, paidBy, createdBy;
  final int amount;
  final DateTime date;
  final Map<String, int> shares;
  final String? receiptPath;
}

class GroupPayment {
  const GroupPayment(this.from, this.to, this.amount, this.date);
  final String from, to;
  final int amount;
  final DateTime date;
}

class GroupLedger {
  const GroupLedger(this.members, this.expenses, this.payments);
  final List<GroupMember> members;
  final List<GroupExpense> expenses;
  final List<GroupPayment> payments;
}

String dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

Map<String, int> splitCents(int amount, Iterable<String> people) {
  final ids = people.toSet().toList()..sort();
  if (amount <= 0 || ids.isEmpty) {
    throw ArgumentError('Choose someone to charge.');
  }
  return {
    for (var i = 0; i < ids.length; i++)
      ids[i]: amount ~/ ids.length + (i < amount % ids.length ? 1 : 0),
  };
}
