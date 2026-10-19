/// Integer-only rounding, nearest cent with ties away from zero.
int roundRatio(int value, int denominator) =>
    value.sign * ((value.abs() + denominator ~/ 2) ~/ denominator);

enum BudgetPeriod {
  week('W'),
  month('M'),
  year('Y');

  const BudgetPeriod(this.label);
  final String label;
  int convert(int monthly) => switch (this) {
    week => roundRatio(monthly * 12, 52),
    month => monthly,
    year => monthly * 12,
  };
}

enum SavingsMode { fixed, percent }

enum ItemKind {
  bill('bill'),
  subscription('subscription'),
  oneTime('one_time');

  const ItemKind(this.databaseValue);
  final String databaseValue;
}

class BudgetItem {
  BudgetItem(this.name, this.amount, this.kind);
  final String name;
  final int amount;
  final ItemKind kind;
}

class Spending {
  Spending(this.description, this.amount, this.date);
  final String description;
  final int amount;
  final DateTime date;
}

class PersonalBudget {
  PersonalBudget({
    this.earnings = 0,
    this.savingsMode = SavingsMode.fixed,
    this.savingsValue = 0,
    List<BudgetItem> items = const [],
    List<Spending> transactions = const [],
  }) : items = List.unmodifiable(items),
       transactions = List.unmodifiable(transactions) {
    if (earnings < 0 ||
        savingsValue < 0 ||
        (savingsMode == SavingsMode.percent && savingsValue > 100) ||
        items.any((i) => i.amount < 0 || i.name.trim().isEmpty) ||
        transactions.any(
          (t) => t.amount <= 0 || t.description.trim().isEmpty,
        )) {
      throw ArgumentError('Invalid budget');
    }
  }
  final int earnings;
  final SavingsMode savingsMode;
  final int savingsValue;
  final List<BudgetItem> items;
  final List<Spending> transactions;
  int total(ItemKind kind) =>
      items.where((i) => i.kind == kind).fold(0, (sum, i) => sum + i.amount);
  int get savings => savingsMode == SavingsMode.fixed
      ? savingsValue
      : roundRatio(
          (earnings - total(ItemKind.bill)).clamp(0, earnings) * savingsValue,
          100,
        );
  int get spent => transactions.fold(0, (sum, t) => sum + t.amount);
  int get spendingMoney =>
      earnings -
      total(ItemKind.bill) -
      savings -
      total(ItemKind.subscription) -
      total(ItemKind.oneTime) -
      spent;
  PersonalBudget copyWith({
    int? earnings,
    SavingsMode? savingsMode,
    int? savingsValue,
    List<BudgetItem>? items,
    List<Spending>? transactions,
  }) => PersonalBudget(
    earnings: earnings ?? this.earnings,
    savingsMode: savingsMode ?? this.savingsMode,
    savingsValue: savingsValue ?? this.savingsValue,
    items: items ?? this.items,
    transactions: transactions ?? this.transactions,
  );
  factory PersonalBudget.example() => PersonalBudget(
    earnings: 240000,
    savingsMode: SavingsMode.percent,
    savingsValue: 15,
    items: [
      BudgetItem('Rent', 90000, ItemKind.bill),
      BudgetItem('Utilities', 12000, ItemKind.bill),
      BudgetItem('Cell plan', 4500, ItemKind.bill),
      BudgetItem('Music', 1099, ItemKind.subscription),
      BudgetItem('Streaming', 1649, ItemKind.subscription),
      BudgetItem('New shoes', 8500, ItemKind.oneTime),
    ],
  );
}

/// Accept dollars with up to two decimals. Never convert money through double.
int? parseCents(String input) {
  final text = input.trim();
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
}

String editDollars(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
String dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
