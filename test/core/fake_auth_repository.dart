import 'package:budget_app/core/auth/auth_repository.dart';

/// In-memory stand-in so widget tests never touch the network.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.displayName, this.signInFailures = 0});

  String? displayName;

  /// How many ensureSignedIn calls throw before one succeeds.
  int signInFailures;

  final List<String> saved = [];
  int signInCalls = 0;

  @override
  Future<String> ensureSignedIn() async {
    signInCalls++;
    if (signInFailures > 0) {
      signInFailures--;
      throw Exception('offline');
    }
    return 'fake-user-id';
  }

  @override
  Future<String?> loadDisplayName(String userId) async => displayName;

  @override
  Future<void> saveDisplayName(String userId, String name) async {
    saved.add(name);
    displayName = name;
  }
}
