import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../group/group_models.dart';
import '../group/group_repository.dart';
import '../personal/budget.dart' show parseCents, editDollars;

class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    super.key,
    required this.repository,
    required this.groupId,
    required this.payer,
    required this.outstanding,
    required this.today,
  });
  final GroupRepository repository;
  final String groupId;
  final GroupMember payer;
  final int outstanding;
  final DateTime today;
  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: editDollars(widget.outstanding),
  );
  late DateTime _date = DateTime(
    widget.today.year,
    widget.today.month,
    widget.today.day,
  );
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = parseCents(_amount.text);
    if (widget.payer.id == widget.repository.userId ||
        amount == null ||
        amount <= 0 ||
        amount > widget.outstanding) {
      setState(
        () => _error =
            'Enter an amount from \$0.01 to ${formatCents(widget.outstanding)}.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.recordReceivedPayment(
        widget.groupId,
        widget.payer.id,
        amount,
        _date,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not record payment. Please try again.';
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
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.payer.name} paid me',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Record only money you have received. This does not transfer money.',
            ),
            TextField(
              key: const Key('payment-amount'),
              controller: _amount,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount received (dollars)',
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(dateOnly(_date)),
              onPressed: _saving
                  ? null
                  : () async {
                      final chosen = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(
                          widget.today.year,
                          widget.today.month,
                          widget.today.day,
                        ),
                      );
                      if (chosen != null && mounted) {
                        setState(() => _date = chosen);
                      }
                    },
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Recording…' : 'Record received payment'),
            ),
          ],
        ),
      ),
    ),
  );
}
