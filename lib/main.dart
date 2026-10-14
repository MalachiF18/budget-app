import 'package:budget_app/core/app.dart';
import 'package:budget_app/core/auth/auth_repository.dart';
import 'package:budget_app/core/supabase_config.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(BudgetApp(auth: SupabaseAuthRepository(Supabase.instance.client)));
}
