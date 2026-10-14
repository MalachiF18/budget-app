import 'package:flutter/material.dart';

/// Placeholder; the real screen is built in card 2.3.
class PersonalScreen extends StatelessWidget {
  const PersonalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal')),
      body: const Center(child: Text('Personal screen coming in card 2.3')),
    );
  }
}
