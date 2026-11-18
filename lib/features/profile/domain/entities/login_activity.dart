class LoginActivity {
  const LoginActivity({
    required this.id,
    required this.at,
    this.platform,
    this.ip,
    this.city,
  });

  final String id;
  final DateTime at;
  final String? platform;
  final String? ip;
  final String? city;
}

class MediaInfo {
  const MediaInfo({
    required this.id,
    required this.url,
    required this.purpose,
  });

  final String id;
  final String url;
  final String purpose;
}
