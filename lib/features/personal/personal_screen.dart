import 'package:budget_app/core/money.dart';
import 'package:budget_app/core/theme.dart';
import 'package:flutter/material.dart';

import 'budget.dart';
import 'budget_repository.dart';
import 'budget_sheets.dart';

class PersonalScreen extends StatefulWidget {
  const PersonalScreen({
    super.key,
    this.repository,
    this.now,
    this.isDemo = false,
  });
  final BudgetRepository? repository;
  final DateTime Function()? now;
  final bool isDemo;
  @override
  State<PersonalScreen> createState() => _PersonalScreenState();
}

class _PersonalScreenState extends State<PersonalScreen> {
  PersonalBudget? _budget;
  bool _failed = false;
  BudgetPeriod _period = BudgetPeriod.month;
  late DateTime _month;
  DateTime get _today => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final today = _today;
    _month = DateTime(today.year, today.month);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _budget = null;
    });
    try {
      final budget =
          await widget.repository?.load(_month) ?? PersonalBudget.example();
      if (mounted) setState(() => _budget = budget);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _save(PersonalBudget budget) async {
    await widget.repository?.save(budget, _month);
    if (mounted) setState(() => _budget = budget);
  }

  Future<void> _edit({ItemKind? kind, bool savings = false}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BudgetEditSheet(
        budget: _budget!,
        kind: kind,
        savings: savings,
        onSave: _save,
      ),
    );
  }

  Future<void> _transaction() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TransactionSheet(
        today: _today,
        onSave: (transaction) async {
          await widget.repository?.addTransaction(transaction);
          if (!mounted) return;
          if (transaction.date.year == _month.year &&
              transaction.date.month == _month.month) {
            setState(
              () => _budget = _budget!.copyWith(
                transactions: [..._budget!.transactions, transaction]
                  ..sort((a, b) => b.date.compareTo(a.date)),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final budget = _budget;
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _failed
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load your budget.'),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : budget == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: personalAccent,
                            size: 23,
                          ),
                          const SizedBox(width: 9),
                          const Expanded(
                            child: Text(
                              'Split & Spend',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (widget.repository == null || widget.isDemo)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF403114),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: const Text(
                                'Example data',
                                style: TextStyle(
                                  color: Color(0xFFF5B441),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          const Text(
                            'Personal',
                            style: TextStyle(
                              fontSize: 34,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SegmentedButton<BudgetPeriod>(
                            showSelectedIcon: false,
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? personalAccent
                                    : personalSurface,
                              ),
                              foregroundColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? personalBackground
                                    : personalMuted,
                              ),
                              textStyle: const WidgetStatePropertyAll(
                                TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              side: const WidgetStatePropertyAll(
                                BorderSide(color: personalBorder),
                              ),
                              padding: const WidgetStatePropertyAll(
                                EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 12,
                                ),
                              ),
                              shape: WidgetStatePropertyAll(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            segments: BudgetPeriod.values
                                .map(
                                  (p) => ButtonSegment(
                                    value: p,
                                    label: Text(p.label),
                                  ),
                                )
                                .toList(),
                            selected: {_period},
                            onSelectionChanged: (value) =>
                                setState(() => _period = value.single),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            budget.spendingMoney >= 0
                                ? "You're doing WELL"
                                : "You're doing BAD",
                            style: TextStyle(
                              color: budget.spendingMoney >= 0
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                          Text(
                            'showing per ${switch (_period) {
                              BudgetPeriod.week => 'week',
                              BudgetPeriod.month => 'month',
                              BudgetPeriod.year => 'year',
                            }}',
                            style: const TextStyle(
                              color: personalMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _card(
                        'Your earnings',
                        budget.earnings,
                        budget,
                        () => _edit(),
                      ),
                      _card(
                        'Necessary bills',
                        budget.total(ItemKind.bill),
                        budget,
                        () => _edit(kind: ItemKind.bill),
                      ),
                      _card(
                        'Savings target',
                        budget.savings,
                        budget,
                        () => _edit(savings: true),
                      ),
                      _card(
                        'Subscriptions',
                        budget.total(ItemKind.subscription),
                        budget,
                        () => _edit(kind: ItemKind.subscription),
                      ),
                      _card(
                        'One-time needs',
                        budget.total(ItemKind.oneTime),
                        budget,
                        () => _edit(kind: ItemKind.oneTime),
                      ),
                      _card(
                        'Spending money',
                        budget.spendingMoney,
                        budget,
                        null,
                      ),
                      FilledButton.icon(
                        onPressed: _transaction,
                        icon: const Icon(Icons.add),
                        label: const Text('Add transaction'),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Recent transactions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (budget.transactions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No spending logged this month.'),
                        ),
                      for (final transaction in budget.transactions.take(10))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(transaction.description),
                          subtitle: Text(dateOnly(transaction.date)),
                          trailing: Text('-${formatCents(transaction.amount)}'),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _card(
    String title,
    int amount,
    PersonalBudget budget,
    VoidCallback? onTap,
  ) {
    final progress = budget.earnings == 0
        ? 0.0
        : (amount / budget.earnings).clamp(0.0, 1.0);
    final fraction = budget.earnings == 0
        ? 0
        : (amount * 100 / budget.earnings).round();
    final kind = switch (title) {
      'Necessary bills' => ItemKind.bill,
      'Subscriptions' => ItemKind.subscription,
      'One-time needs' => ItemKind.oneTime,
      _ => null,
    };
    final names = kind == null
        ? ''
        : budget.items
              .where((i) => i.kind == kind)
              .map((i) => i.name)
              .join(', ');
    final detail = switch (title) {
      'Your earnings' => 'Expected monthly pay',
      'Savings target' =>
        budget.savingsMode == SavingsMode.percent
            ? '${budget.savingsValue}% of money after bills · $fraction% of earnings'
            : 'Fixed monthly target · $fraction% of earnings',
      'Spending money' =>
        'After bills, savings, subscriptions, needs and logged spending',
      _ => '${names.isEmpty ? 'No items yet' : names} · $fraction% of earnings',
    };
    final suffix = switch (_period) {
      BudgetPeriod.week => '/wk',
      BudgetPeriod.month => '/mo',
      BudgetPeriod.year => '/yr',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: title == 'Necessary bills' ? personalAccent : personalBorder,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      const Text(
                        'Edit',
                        style: TextStyle(
                          color: personalAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 3,
                  children: [
                    Text(
                      formatCents(_period.convert(amount)),
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        suffix,
                        style: const TextStyle(
                          color: personalMuted,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: personalBorder,
                  color: amount < 0
                      ? Colors.red
                      : title == 'Savings target'
                      ? const Color(0xFF46CF7C)
                      : personalAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 10),
                Text(
                  detail,
                  style: const TextStyle(
                    color: personalMuted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
