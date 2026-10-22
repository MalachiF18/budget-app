import 'package:budget_app/core/app.dart';
import 'package:budget_app/core/auth/auth_repository.dart';
import 'package:budget_app/core/supabase_config.dart';
import 'package:flutter/material.dart';

import 'demo/demo_repositories.dart';
import 'features/group/group_repository.dart';

import 'package:budget_app/features/personal/budget_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('DEMO_MODE')) {
    runApp(
      BudgetApp(
        auth: DemoAuthRepository(),
        budgets: DemoBudgetRepository(),
        groups: DemoGroupRepository(),
        demoMode: true,
      ),
    );
    return;
  }
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(
    BudgetApp(
      auth: SupabaseAuthRepository(Supabase.instance.client),
      budgets: SupabaseBudgetRepository(Supabase.instance.client),
      groups: SupabaseGroupRepository(Supabase.instance.client),
    ),
  );
}
