import 'package:budget_app/core/auth/auth_repository.dart';
import 'package:budget_app/core/auth/name_screen.dart';
import 'package:flutter/material.dart';

/// Gate in front of the app: sign in, make sure there is a display name, then
/// show [builder]'s content (the tab shell).
class StartupGate extends StatefulWidget {
  const StartupGate({super.key, required this.auth, required this.builder});

  final AuthRepository auth;
  final WidgetBuilder builder;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

enum _Phase { loading, failed, needsName, ready }

class _StartupGateState extends State<StartupGate> {
  _Phase _phase = _Phase.loading;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _phase = _Phase.loading);
    try {
      final id = await widget.auth.ensureSignedIn();
      final name = await widget.auth.loadDisplayName(id);
      if (!mounted) return;
      setState(() {
        _userId = id;
        _phase = name == null ? _Phase.needsName : _Phase.ready;
      });
    } catch (_) {
      // Offline or server trouble: offer Retry rather than crashing.
      if (!mounted) return;
      setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _saveName(String name) async {
    await widget.auth.saveDisplayName(_userId!, name);
    if (!mounted) return;
    setState(() => _phase = _Phase.ready);
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _Phase.failed:
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Couldn't sign in. Check your connection."),
                const SizedBox(height: 16),
                FilledButton(onPressed: _start, child: const Text('Retry')),
              ],
            ),
          ),
        );
      case _Phase.needsName:
        return NameScreen(onSave: _saveName);
      case _Phase.ready:
        return widget.builder(context);
    }
  }
}
