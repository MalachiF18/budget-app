import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sign-in and display-name storage. An interface so widget tests can use a
/// fake and never hit the network (repository pattern).
abstract interface class AuthRepository {
  /// Returns the signed-in user id; signs in anonymously if there is no session.
  Future<String> ensureSignedIn();

  /// The user's display name, or null if they haven't picked one yet.
  Future<String?> loadDisplayName(String userId);

  Future<void> saveDisplayName(String userId, String name);
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> ensureSignedIn() async {
    // A stored session survives app restarts, so anonymous sign-in only
    // happens once per install.
    var user = _client.auth.currentUser;
    user ??= (await _client.auth.signInAnonymously()).user;
    if (user == null) throw StateError('Sign-in returned no user');
    if (kDebugMode) debugPrint('signed in as ${user.id}');
    return user.id;
  }

  @override
  Future<String?> loadDisplayName(String userId) async {
    final row = await _client
        .from('profiles')
        .select('display_name')
        .eq('id', userId)
        .maybeSingle();
    return row?['display_name'] as String?;
  }

  @override
  Future<void> saveDisplayName(String userId, String name) async {
    // Upsert on the primary key: first save inserts, later saves update.
    await _client.from('profiles').upsert({'id': userId, 'display_name': name});
  }
}
