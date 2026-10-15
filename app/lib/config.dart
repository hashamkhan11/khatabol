/// Supabase connection. The publishable key is public by design: every table
/// is protected by row-level security, and all writes go through database
/// functions that check the signed-in user.
///
/// Override for another project with:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class Config {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://whdfxvxvvpsjveiuhgwn.supabase.co',
  );
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_csIWBU46_V6DDGdYd6E01g_RRF3O-9w',
  );
}
