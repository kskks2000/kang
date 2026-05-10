class AppUser {
  const AppUser({
    required this.id,
    required this.firebaseUid,
    required this.userName,
    required this.userType,
    required this.roleCode,
    this.email,
    this.displayName,
    this.photoUrl,
    this.userNo,
  });

  final String id;
  final String firebaseUid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final int? userNo;
  final String userName;
  final String userType;
  final String roleCode;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      firebaseUid: json['firebase_uid'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      photoUrl: json['photo_url'] as String?,
      userNo: json['user_no'] as int?,
      userName: json['user_name'] as String,
      userType: json['user_type'] as String,
      roleCode: json['role_code'] as String,
    );
  }
}
