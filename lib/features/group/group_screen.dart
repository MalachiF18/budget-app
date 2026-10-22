import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/money.dart';
import '../balances/balance_engine.dart';
import '../balances/payment_sheet.dart';
import 'group_models.dart';
import 'group_repository.dart';
import 'expense_form.dart';

class GroupScreen extends StatefulWidget {
  const GroupScreen({
    super.key,
    this.repository,
    this.active = true,
    this.now,
    this.isDemo = false,
  });
  final GroupRepository? repository;
  final bool active;
  final DateTime Function()? now;
  final bool isDemo;
  DateTime get today => (now ?? DateTime.now)();
  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> with WidgetsBindingObserver {
  GroupRepository? _repository;
  List<SpendingGroup> _groups = [];
  SpendingGroup? _group;
  GroupLedger? _ledger;
  StreamSubscription<void>? _subscription;
  String _period = 'ALL';
  String? _member, _error;
  bool _busy = true;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _repository =
          widget.repository ??
          SupabaseGroupRepository(Supabase.instance.client);
    } catch (_) {
      _busy = false;
      _error = 'Connect to Supabase to load your groups.';
    }
    if (_repository != null) unawaited(_loadGroups());
  }

  @override
  void didUpdateWidget(covariant GroupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && _repository != null) {
      unawaited(_loadGroups());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _group != null) {
      unawaited(_refresh());
    }
  }

  Future<void> _loadGroups([String? selected]) async {
    try {
      final groups = await _repository!.groups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _busy = false;
        _error = null;
      });
      if (groups.isNotEmpty) {
        final matches = groups.where((g) => g.id == (selected ?? _group?.id));
        await _open(matches.isEmpty ? groups.first : matches.first);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not load groups: $e';
        });
      }
    }
  }

  Future<void> _open(SpendingGroup group) async {
    await _subscription?.cancel();
    if (!mounted) return;
    setState(() {
      _group = group;
      _ledger = null;
      _member = null;
      _period = 'ALL';
      _busy = true;
    });
    _subscription = _repository!
        .changes(group.id)
        .listen(
          (_) => unawaited(_refresh()),
          onError: (Object e) {
            if (mounted) {
              setState(
                () => _error =
                    'Live connection interrupted. Pull down to refresh.',
              );
            }
          },
        );
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_group == null) return;
    final request = ++_request;
    try {
      final ledger = await _repository!.load(_group!.id);
      if (mounted && request == _request) {
        setState(() {
          _ledger = ledger;
          _busy = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _busy = false;
          _error = 'Could not load expenses: $e';
        });
      }
    }
  }

  Future<void> _entry(bool create) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _GroupEntry(create: create, repository: _repository!),
    );
    if (value != null && mounted) await _loadGroups(value);
  }

  Future<void> _edit([GroupExpense? expense]) async {
    if (expense != null && expense.createdBy != _repository!.userId) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseForm(
          repository: _repository!,
          groupId: _group!.id,
          members: _ledger!.members,
          expense: expense,
        ),
      ),
    );
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _delete(GroupExpense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(expense.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository!.delete(expense);
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not delete expense: $e');
    }
  }

  ActivityPeriod get _activityPeriod =>
      ActivityPeriod.values.firstWhere((p) => p.label == _period);
  Future<void> _receive(GroupMember member, int outstanding) async {
    if (member.id == _repository!.userId || outstanding <= 0) return;
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PaymentSheet(
        repository: _repository!,
        groupId: _group!.id,
        payer: member,
        outstanding: outstanding,
        today: widget.today,
      ),
    );
    if (recorded == true && mounted) await _refresh();
  }

  String _name(String id) =>
      _ledger!.members
          .where((m) => m.id == id)
          .map((m) => m.name)
          .firstOrNull ??
      'Member';
  @override
  Widget build(BuildContext context) {
    final activity = _ledger == null
        ? null
        : GroupActivity(_ledger!, _activityPeriod, widget.today);
    final engine = _ledger == null ? null : BalanceEngine(_ledger!);
    final entries = activity?.ledgerFor(_member) ?? <LedgerEntry>[];
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_group?.name ?? 'Group'),
        actions: [
          IconButton(
            tooltip: 'Create group',
            onPressed: _repository == null ? null : () => _entry(true),
            icon: const Icon(Icons.group_add_outlined),
          ),
          TextButton(
            onPressed: _repository == null ? null : () => _entry(false),
            child: const Text('Join'),
          ),
        ],
      ),
      floatingActionButton: _ledger == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
      body: _busy && _ledger == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadGroups(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (widget.isDemo)
                    const Text(
                      'Example data · demo only',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: scheme.error)),
                    TextButton(
                      onPressed: _repository == null
                          ? null
                          : () => _loadGroups(),
                      child: const Text('Retry'),
                    ),
                  ],
                  if (_group == null) ...[
                    const SizedBox(height: 60),
                    const Icon(Icons.groups_outlined, size: 72),
                    const SizedBox(height: 16),
                    Text(
                      'Split & Spend together',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Create a group or join with a sync code.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _repository == null
                          ? null
                          : () => _entry(true),
                      child: const Text('Create group'),
                    ),
                    OutlinedButton(
                      onPressed: _repository == null
                          ? null
                          : () => _entry(false),
                      child: const Text('Join group'),
                    ),
                  ] else ...[
                    if (_groups.length > 1)
                      DropdownButton<String>(
                        isExpanded: true,
                        value: _group!.id,
                        items: _groups
                            .map(
                              (g) => DropdownMenuItem(
                                value: g.id,
                                child: Text(g.name),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          if (id != null) {
                            unawaited(
                              _open(_groups.firstWhere((g) => g.id == id)),
                            );
                          }
                        },
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Sync code'),
                                  SelectableText(
                                    _group!.code,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy sync code',
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: _group!.code),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Sync code copied'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'W', label: Text('W')),
                        ButtonSegment(value: 'M', label: Text('M')),
                        ButtonSegment(value: 'ALL', label: Text('ALL')),
                      ],
                      selected: {_period},
                      onSelectionChanged: (v) =>
                          setState(() => _period = v.first),
                    ),
                    const SizedBox(height: 20),
                    const Text('Total spent'),
                    Text(
                      formatCents(activity?.totalSpent ?? 0),
                      key: const ValueKey('group-total'),
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    Text(
                      '${_activityPeriod.description} activity · balances are all time',
                    ),
                    const SizedBox(height: 24),
                    if (_ledger != null)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 600
                              ? 3
                              : constraints.maxWidth >= 320
                              ? 2
                              : 1;
                          final width =
                              (constraints.maxWidth - (columns - 1) * 12) /
                              columns;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: _ledger!.members.map((m) {
                              final paid = activity!.spentBy(m.id);
                              final self = m.id == _repository!.userId;
                              final pair = self
                                  ? engine!.totalsFor(m.id)
                                  : engine!.between(_repository!.userId, m.id);
                              return SizedBox(
                                width: width,
                                child: Card(
                                  color: _member == m.id
                                      ? scheme.primaryContainer
                                      : null,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => setState(() => _member = m.id),
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CircleAvatar(
                                            child: Text(
                                              m.name.isEmpty
                                                  ? '?'
                                                  : m.name
                                                        .substring(0, 1)
                                                        .toUpperCase(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            '${m.name}${m.id == _repository!.userId ? ' (You)' : ''}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const SizedBox(height: 8),
                                          Text('Spent ${formatCents(paid)}'),
                                          const SizedBox(height: 8),
                                          Text(
                                            '${self ? 'You owe others' : 'You owe them'} ${formatCents(pair.youOwe)}',
                                            key: ValueKey('owe-${m.id}'),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: pair.youOwe > 0
                                                  ? Colors.red
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${self ? 'Others owe you' : 'They owe you'} ${formatCents(pair.theyOwe)}',
                                            key: ValueKey('owed-${m.id}'),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: pair.theyOwe > 0
                                                  ? Colors.green
                                                  : null,
                                            ),
                                          ),
                                          if (!self && pair.theyOwe > 0)
                                            TextButton(
                                              key: ValueKey('receive-${m.id}'),
                                              onPressed: () =>
                                                  _receive(m, pair.theyOwe),
                                              child: const Text(
                                                'Record received payment',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _member == null
                                ? 'Group ledger'
                                : '${_name(_member!)} ledger',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (_member != null)
                          TextButton(
                            onPressed: () => setState(() => _member = null),
                            child: const Text('Show all'),
                          ),
                      ],
                    ),
                    if (entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No activity for this selection.'),
                      ),
                    for (final entry in entries)
                      if (entry.payment != null)
                        _paymentCard(entry.payment!)
                      else
                        _expenseCard(entry.expense!),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _paymentCard(GroupPayment payment) => Card(
    child: ListTile(
      leading: const Icon(Icons.payments_outlined),
      title: Text(
        '${_name(payment.from)} paid ${payment.to == _repository!.userId ? 'you' : _name(payment.to)}',
      ),
      subtitle: Text('${dateOnly(payment.date)} • Payment received'),
      trailing: Text(formatCents(payment.amount)),
    ),
  );

  Widget _expenseCard(GroupExpense e) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.description,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(formatCents(e.amount)),
            ],
          ),
          const SizedBox(height: 8),
          Text('${dateOnly(e.date)} • Paid by ${_name(e.paidBy)}'),
          Text('Split with: ${e.shares.keys.map(_name).join(', ')}'),
          Wrap(
            children: [
              if (e.receiptPath != null)
                IconButton(
                  tooltip: 'View receipt',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _ReceiptView(
                        repository: _repository!,
                        path: e.receiptPath!,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long),
                ),
              if (e.createdBy == _repository!.userId) ...[
                TextButton(
                  onPressed: () => _edit(e),
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: () => _delete(e),
                  child: const Text('Delete'),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

class _GroupEntry extends StatefulWidget {
  const _GroupEntry({required this.create, required this.repository});
  final bool create;
  final GroupRepository repository;
  @override
  State<_GroupEntry> createState() => _GroupEntryState();
}

class _GroupEntryState extends State<_GroupEntry> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_text.text.trim().isEmpty) {
      setState(
        () =>
            _error = 'Enter ${widget.create ? 'a group name' : 'a sync code'}.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.create
          ? await widget.repository.create(_text.text.trim())
          : await widget.repository.join(_text.text.trim());
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _busy = false;
          _error = 'No group found. Check the sync code.';
        });
      } else {
        Navigator.pop(context, id);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.create ? 'Create group' : 'Join group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _text,
            enabled: !_busy,
            autofocus: true,
            maxLength: widget.create ? 60 : 40,
            decoration: InputDecoration(
              labelText: widget.create ? 'Group name' : 'Sync code',
              errorText: _error,
            ),
            onSubmitted: (_) {
              if (!_busy) _submit();
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(
            _busy
                ? 'Please wait…'
                : widget.create
                ? 'Create'
                : 'Join',
          ),
        ),
      ],
    ),
  );
}

class _ReceiptView extends StatefulWidget {
  const _ReceiptView({required this.repository, required this.path});
  final GroupRepository repository;
  final String path;
  @override
  State<_ReceiptView> createState() => _ReceiptViewState();
}

class _ReceiptViewState extends State<_ReceiptView> {
  late final Future<Uint8List> _image = widget.repository.receipt(widget.path);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Receipt')),
    body: FutureBuilder<Uint8List>(
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Could not load receipt. Go back and try again.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: InteractiveViewer(
            child: Image.memory(
              snapshot.data!,
              errorBuilder: (_, _, _) =>
                  const Text('Could not display receipt.'),
            ),
          ),
        );
      },
    ),
  );
}
