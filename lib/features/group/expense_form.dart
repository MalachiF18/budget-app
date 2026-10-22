import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'group_models.dart';
import 'group_repository.dart';

class ExpenseForm extends StatefulWidget {
  const ExpenseForm({
    super.key,
    required this.repository,
    required this.groupId,
    required this.members,
    this.expense,
  });
  final GroupRepository repository;
  final String groupId;
  final List<GroupMember> members;
  final GroupExpense? expense;
  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _description, _amount;
  late DateTime _date;
  late Set<String> _selected;
  bool _share = true, _saving = false;
  Uint8List? _photo;
  String? _error;
  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _description = TextEditingController(text: e?.description);
    _amount = TextEditingController(
      text: e == null
          ? ''
          : '${e.amount ~/ 100}.${(e.amount % 100).toString().padLeft(2, '0')}',
    );
    _date = e?.date ?? DateTime.now();
    _selected = {...?e?.shares.keys}..remove(widget.repository.userId);
    _share = e == null || e.shares.containsKey(widget.repository.userId);
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 5242880)
        throw ArgumentError('Choose a photo under 5 MiB.');
      if (mounted)
        setState(() {
          _photo = bytes;
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not attach photo: $e');
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final people = {..._selected, if (_share) widget.repository.userId};
    if (people.isEmpty) {
      setState(
        () => _error = 'Choose someone to charge or turn on Share with me.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String? uploaded;
    try {
      final parts = _amount.text.trim().split('.');
      final cents =
          int.parse(parts[0]) * 100 +
          (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
      if (_photo != null)
        uploaded = await widget.repository.upload(widget.groupId, _photo!);
      final old = widget.expense;
      await widget.repository.save(
        widget.groupId,
        GroupExpense(
          id: old?.id ?? '',
          description: _description.text.trim(),
          amount: cents,
          date: _date,
          paidBy: old?.paidBy ?? widget.repository.userId,
          createdBy: old?.createdBy ?? widget.repository.userId,
          shares: splitCents(cents, people),
          receiptPath: uploaded ?? old?.receiptPath,
        ),
      );
      if (uploaded != null && old?.receiptPath != null) {
        try {
          await widget.repository.removeReceipt(old!.receiptPath!);
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (uploaded != null) {
        try {
          await widget.repository.removeReceipt(uploaded);
        } catch (_) {}
      }
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Could not save expense: $e';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final others = widget.members
        .where((m) => m.id != widget.repository.userId)
        .toList();
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.expense == null ? 'Add expense' : 'Edit expense'),
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: _description,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Description'),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter a description.'
                      : null,
                ),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '\$',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$')
                            .hasMatch(v?.trim() ?? '') ||
                        (num.tryParse(v!.trim()) ?? 0) <= 0)
                      return 'Enter a positive amount with up to two decimal places.';
                    return null;
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(dateOnly(_date)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200),
                    );
                    if (date != null && mounted) setState(() => _date = date);
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Charge who',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: () => setState(
                        () => _selected = others.map((m) => m.id).toSet(),
                      ),
                      child: const Text('Select all'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _selected.clear()),
                      child: const Text('Deselect all'),
                    ),
                  ],
                ),
                for (final m in others)
                  CheckboxListTile(
                    key: ValueKey('charge-${m.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(m.name),
                    value: _selected.contains(m.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(m.id);
                      } else {
                        _selected.remove(m.id);
                      }
                    }),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Share with me'),
                  subtitle: const Text('Include my own share in the split'),
                  value: _share,
                  onChanged: (v) => setState(() => _share = v),
                ),
                const SizedBox(height: 16),
                Text(
                  'Receipt (optional)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                  ],
                ),
                if (_photo != null) ...[
                  Image.memory(
                    _photo!,
                    height: 160,
                    errorBuilder: (_, _, _) => const Text('Photo selected'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _photo = null),
                    child: const Text('Discard new photo'),
                  ),
                ] else if (widget.expense?.receiptPath != null)
                  const Text('Existing receipt will be kept.'),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save expense'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
