class FindLoginIdResult {
  const FindLoginIdResult({
    required this.found,
    required this.message,
    this.maskedLoginId,
  });

  final bool found;
  final String message;
  final String? maskedLoginId;

  factory FindLoginIdResult.fromJson(Map<String, dynamic> json) {
    return FindLoginIdResult(
      found: json['found'] as bool,
      message: json['message'] as String,
      maskedLoginId: json['masked_login_id'] as String?,
    );
  }
}
