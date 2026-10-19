import 'package:budget_app/core/money.dart';
import 'package:flutter/material.dart';

import 'budget.dart';
import 'budget_repository.dart';
import 'budget_sheets.dart';

class PersonalScreen extends StatefulWidget {
  const PersonalScreen({super.key, this.repository, this.now});
  final BudgetRepository? repository;
  final DateTime Function()? now;
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
      appBar: AppBar(title: const Text('Personal')),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load your budget.'),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : budget == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Your money, your plan',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Center(
                  child: SegmentedButton<BudgetPeriod>(
                    segments: BudgetPeriod.values
                        .map(
                          (p) => ButtonSegment(value: p, label: Text(p.label)),
                        )
                        .toList(),
                    selected: {_period},
                    onSelectionChanged: (value) =>
                        setState(() => _period = value.single),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _period == BudgetPeriod.month
                      ? 'Monthly budget · ${dateOnly(_month).substring(0, 7)}'
                      : 'Monthly budget projected ${_period == BudgetPeriod.week ? 'weekly' : 'yearly'}',
                ),
                if (widget.repository == null) const Text('Example budget'),
                const SizedBox(height: 12),
                Text(
                  budget.spendingMoney >= 0
                      ? "You're doing WELL"
                      : "You're doing BAD",
                  style: TextStyle(
                    color: budget.spendingMoney >= 0
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 16),
                _card('Your earnings', budget.earnings, budget, () => _edit()),
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
                const Divider(height: 28),
                _card('Spending money', budget.spendingMoney, budget, null),
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
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (onTap != null) const Icon(Icons.edit_outlined, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                formatCents(_period.convert(amount)),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color: amount < 0 ? Colors.red : null,
                borderRadius: BorderRadius.circular(6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
