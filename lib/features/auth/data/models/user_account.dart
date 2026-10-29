class UserAccount {
  final String username;
  final String? email;
  final String? phone;
  final String passwordHash;
  final String salt;
  final DateTime createdAt;

  const UserAccount({
    required this.username,
    this.email,
    this.phone,
    required this.passwordHash,
    required this.salt,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'email': email,
    'phone': phone,
    'password_hash': passwordHash,
    'salt': salt,
    'created_at': createdAt.toIso8601String(),
  };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
    username: json['username'] as String,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    passwordHash: (json['password_hash'] ?? json['passwordHash']) as String,
    salt: json['salt'] as String,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
  );

  UserAccount copyWith({
    String? username,
    String? email,
    String? phone,
    String? passwordHash,
    String? salt,
    DateTime? createdAt,
  }) => UserAccount(
    username: username ?? this.username,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    passwordHash: passwordHash ?? this.passwordHash,
    salt: salt ?? this.salt,
    createdAt: createdAt ?? this.createdAt,
  );

  @override
  String toString() =>
      'UserAccount(username: $username, email: $email, phone: $phone)';
}
