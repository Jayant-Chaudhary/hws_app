class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final int relayCount;
  final String? fcmToken;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.relayCount = 0,
    this.fcmToken,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      relayCount: data['relayCount'] ?? 0,
      fcmToken: data['fcmToken'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'relayCount': relayCount,
      'fcmToken': fcmToken,
    };
  }
}
