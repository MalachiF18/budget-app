import 'package:flutter/material.dart';

const _maxNameLength = 40;

/// First-launch screen asking for a display name.
class NameScreen extends StatefulWidget {
  const NameScreen({super.key, required this.onSave});

  /// Called with the trimmed, validated name. Throwing shows an error and
  /// lets the user try again.
  final Future<void> Function(String name) onSave;

  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _saving = false;
  String? _saveError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Validate the trimmed text: the database also rejects padded names.
  String? _validate(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Enter a name';
    if (name.length > _maxNameLength) return 'Max $_maxNameLength characters';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(_controller.text.trim());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = "Couldn't save your name. Check your connection.";
      });
    }
    // On success the parent swaps this screen out, so nothing more to do.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'What should we call you?',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Friends in your groups will see this name.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validate,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_saveError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _saveError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
