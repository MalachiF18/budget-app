// Safe to commit: the publishable key is meant to ship inside the app. It only
// identifies the project; row-level security in the database is what protects
// the data. The service-role key bypasses that security and must NEVER appear
// in the app, in this repo, or in a --dart-define.
//
// Override per build, e.g. to point at your own Supabase project:
//   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://jjieezdpducfwdxaijwy.supabase.co',
);

const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_jOXhI_k4-KoQz6GJfCIkZg_4aEAkpVn',
);
