import 'package:budget_app/core/theme.dart';
import 'package:budget_app/features/group/group_screen.dart';
import 'package:budget_app/features/personal/personal_screen.dart';
import 'package:flutter/material.dart';

/// App root: MaterialApp plus the Personal | Group bottom-nav shell.
class BudgetApp extends StatefulWidget {
  const BudgetApp({super.key});

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
      theme: _index == 0 ? personalTheme : groupTheme,
      home: Scaffold(
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
      ),
    );
  }
}
