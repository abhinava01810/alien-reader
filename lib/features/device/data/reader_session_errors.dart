/// The reader already has an app session that is not this user's. Nothing
/// was ended; the person decides whether to take it over.
class ReaderInUseException implements Exception {
  const ReaderInUseException(this.holderName);

  /// Display name of whoever holds the session, if the reader said.
  final String? holderName;

  /// "This reader is in use by Priya." / "...in use by someone else."
  String get message => holderName == null || holderName!.isEmpty
      ? 'This reader is in use by someone else.'
      : 'This reader is in use by $holderName.';

  @override
  String toString() => message;
}
