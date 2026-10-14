import 'package:budget_app/core/auth/auth_repository.dart';
import 'package:budget_app/core/startup.dart';
import 'package:budget_app/core/theme.dart';
import 'package:budget_app/features/group/group_screen.dart';
import 'package:budget_app/features/personal/personal_screen.dart';
import 'package:flutter/material.dart';

/// App root: MaterialApp plus the Personal | Group bottom-nav shell, behind a
/// startup gate (sign-in, display name).
class BudgetApp extends StatefulWidget {
  const BudgetApp({super.key, required this.auth});

  /// Injected so tests can pass a fake instead of the network.
  final AuthRepository auth;

  @override
  State<BudgetApp> createState() => _BudgetAppState();
}

class _BudgetAppState extends State<BudgetApp> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Budget App',
      // Theme lives on MaterialApp so the nav bar switches colors with the tab.
      // Startup screens (spinner, name) show under the Personal theme.
      theme: _index == 0 ? personalTheme : groupTheme,
      home: StartupGate(auth: widget.auth, builder: (_) => _buildShell()),
    );
  }

  Widget _buildShell() {
    return Scaffold(
      // IndexedStack keeps both screens mounted so each tab keeps its state.
      body: IndexedStack(
        index: _index,
        children: const [PersonalScreen(), GroupScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Personal',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Group',
          ),
        ],
      ),
    );
  }
}
