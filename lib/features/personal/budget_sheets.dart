import 'package:budget_app/core/money.dart';
import 'package:flutter/material.dart';

import 'budget.dart';

String itemTitle(ItemKind kind) => switch (kind) {
  ItemKind.bill => 'Necessary bills',
  ItemKind.subscription => 'Subscriptions',
  ItemKind.oneTime => 'One-time needs',
};

/// Sheets own their draft; only a successful repository save changes the screen.
class BudgetEditSheet extends StatefulWidget {
  const BudgetEditSheet({
    super.key,
    required this.budget,
    required this.onSave,
    this.kind,
    this.savings = false,
  });
  final PersonalBudget budget;
  final Future<void> Function(PersonalBudget) onSave;
  final ItemKind? kind;
  final bool savings;
  @override
  State<BudgetEditSheet> createState() => _BudgetEditSheetState();
}

class _BudgetEditSheetState extends State<BudgetEditSheet> {
  late final TextEditingController _amount;
  late SavingsMode _mode;
  late List<BudgetItem> _items;
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _mode = widget.budget.savingsMode;
    _items = widget.budget.items.where((i) => i.kind == widget.kind).toList();
    final value = widget.savings
        ? widget.budget.savingsValue
        : widget.budget.earnings;
    _amount = TextEditingController(
      text: widget.savings && _mode == SavingsMode.percent
          ? '$value'
          : editDollars(value),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _item([int? index]) async {
    final item = await showDialog<BudgetItem>(
      context: context,
      builder: (_) => ItemDialog(
        kind: widget.kind!,
        item: index == null ? null : _items[index],
      ),
    );
    if (item != null && mounted) {
      setState(() {
        if (index == null) {
          _items.add(item);
        } else {
          _items[index] = item;
        }
      });
    }
  }

  Future<void> _save() async {
    PersonalBudget draft;
    if (widget.kind != null) {
      draft = widget.budget.copyWith(
        items: [
          ...widget.budget.items.where((i) => i.kind != widget.kind),
          ..._items,
        ],
      );
    } else {
      final percent = widget.savings && _mode == SavingsMode.percent;
      final text = _amount.text.trim();
      final value = percent
          ? (RegExp(r'^\d{1,3}$').hasMatch(text) ? int.tryParse(text) : null)
          : parseCents(text);
      if (value == null || (percent && value > 100)) {
        setState(
          () => _error = percent
              ? 'Enter a whole percent from 0 to 100.'
              : 'Enter a valid amount with up to two decimals.',
        );
        return;
      }
      draft = widget.savings
          ? widget.budget.copyWith(savingsMode: _mode, savingsValue: value)
          : widget.budget.copyWith(earnings: value);
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(draft);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not save. Please try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.kind != null
                  ? itemTitle(widget.kind!)
                  : widget.savings
                  ? 'Savings target'
                  : 'Your earnings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text('Enter monthly amounts. W / Y show projections.'),
            if (widget.savings)
              SegmentedButton<SavingsMode>(
                segments: const [
                  ButtonSegment(
                    value: SavingsMode.fixed,
                    label: Text('Fixed amount'),
                  ),
                  ButtonSegment(
                    value: SavingsMode.percent,
                    label: Text('% after bills'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _mode = value.single;
                        _amount.text = '0';
                        _error = null;
                      }),
              ),
            if (widget.kind == null)
              TextField(
                key: const Key('amount'),
                controller: _amount,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: widget.savings && _mode == SavingsMode.percent
                      ? 'Percent'
                      : 'Amount (dollars)',
                ),
              ),
            if (widget.kind != null) ...[
              for (var index = 0; index < _items.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_items[index].name),
                  subtitle: Text(formatCents(_items[index].amount)),
                  onTap: _saving ? null : () => _item(index),
                  trailing: IconButton(
                    tooltip: 'Remove ${_items[index].name}',
                    onPressed: _saving
                        ? null
                        : () => setState(() => _items.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              TextButton.icon(
                onPressed: _saving ? null : _item,
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
            ],
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    ),
  );
}

class ItemDialog extends StatefulWidget {
  const ItemDialog({super.key, required this.kind, this.item});
  final ItemKind kind;
  final BudgetItem? item;
  @override
  State<ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<ItemDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.item?.name,
  );
  late final TextEditingController _amount = TextEditingController(
    text: editDollars(widget.item?.amount ?? 0),
  );
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.item == null ? 'Add item' : 'Edit item'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('description'),
            controller: _name,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            key: const Key('amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (dollars)'),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final amount = parseCents(_amount.text);
          if (_name.text.trim().isEmpty || amount == null) {
            setState(() => _error = 'Enter a name and valid amount.');
            return;
          }
          Navigator.pop(
            context,
            BudgetItem(_name.text.trim(), amount, widget.kind),
          );
        },
        child: const Text('Done'),
      ),
    ],
  );
}

class TransactionSheet extends StatefulWidget {
  const TransactionSheet({
    super.key,
    required this.today,
    required this.onSave,
  });
  final DateTime today;
  final Future<void> Function(Spending) onSave;
  @override
  State<TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends State<TransactionSheet> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  late DateTime _date = DateTime(
    widget.today.year,
    widget.today.month,
    widget.today.day,
  );
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseCents(_amount.text);
    if (_description.text.trim().isEmpty || amount == null || amount <= 0) {
      setState(
        () => _error = 'Enter a description and an amount greater than zero.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(Spending(_description.text.trim(), amount, _date));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add transaction',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextField(
              key: const Key('description'),
              controller: _description,
              enabled: !_saving,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              key: const Key('amount'),
              controller: _amount,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount (dollars)'),
            ),
            TextButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(dateOnly(_date)),
              onPressed: _saving
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200),
                      );
                      if (date != null && mounted) setState(() => _date = date);
                    },
            ),
            const Text('Transactions count toward the month of their date.'),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    ),
  );
}
