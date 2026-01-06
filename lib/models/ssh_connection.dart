class SSHConnectionConfig {
  final String name;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;

  SSHConnectionConfig({
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'privateKey': privateKey,
      };

  factory SSHConnectionConfig.fromJson(Map<String, dynamic> json) {
    return SSHConnectionConfig(
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      username: json['username'] as String,
      password: json['password'] as String?,
      privateKey: json['privateKey'] as String?,
    );
  }

  SSHConnectionConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? privateKey,
  }) {
    return SSHConnectionConfig(
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
    );
  }
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}
