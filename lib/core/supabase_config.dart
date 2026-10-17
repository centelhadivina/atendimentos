import 'dart:convert';

class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.publishableKey});
  factory SupabaseConfig.fromEnvironment() => const SupabaseConfig(
    url: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );
  final String url, publishableKey;
  void validate() {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host)))) {
      throw const FormatException(
        'Configure SUPABASE_URL com a URL do projeto.',
      );
    }
    var isPublic = publishableKey.startsWith('sb_publishable_');
    if (!isPublic && publishableKey.split('.').length == 3) {
      try {
        final payload = jsonDecode(
          utf8.decode(
            base64Url.decode(base64Url.normalize(publishableKey.split('.')[1])),
          ),
        ) as Map;
        isPublic = payload['role'] == 'anon';
      } on Object {
        isPublic = false;
      }
    }
    if (!isPublic) {
      throw const FormatException(
        'Configure SUPABASE_PUBLISHABLE_KEY com uma chave pública publishable ou anon.',
      );
    }
  }
}
