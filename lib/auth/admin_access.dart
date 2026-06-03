// Admin access is now enforced entirely server-side via Firestore Security Rules
// and the `role` field on each user document in Firestore.
// This file is kept as a stub so existing imports don't break.
class AdminAccess {
  AdminAccess._();

  /// Always returns true — real enforcement happens in Firestore Security Rules.
  /// The `role` field on the user document is the single source of truth.
  static bool isAllowedAdminEmail(String? email) => true;
}
