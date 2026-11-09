/// Valide les URLs de pages distantes avant de les confier a une WebView.
/// Les liens locaux, javascript:, data:, http: et les URLs avec identifiants
/// embarques ne sont pas des pages de lecture admissibles.
Uri? safeReadingUri(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}
