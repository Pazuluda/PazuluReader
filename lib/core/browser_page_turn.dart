import 'dart:convert';

/// Runs *only* on the current already-open chapter. Changes the existing
/// public page dropdown through its normal change events. It does not fetch
/// hidden content, guess URLs or bypass site restrictions.
String browserTurnToPageScript(int page, int selectIndex) {
  if (page < 1 || page > 300 || selectIndex < 0 || selectIndex >= 50) {
    throw ArgumentError('Indice de pagination invalide.');
  }
  return '''
(() => {
  const select = document.querySelectorAll('select')[$selectIndex];
  if (!select) return JSON.stringify({accepted:false, reason:'select absent'});
  const labels = [...select.options].map(option => {
    const match = (option.textContent || '').trim().match(/^(?:page\\s*)?(\\d+)(?:\\s*\\/\\s*\\d+)?\$/i);
    return match ? Number(match[1]) : null;
  });
  const index = labels.indexOf($page);
  if (index < 0 || new Set(labels).size !== labels.length ||
      labels[0] === null || !labels.includes(1) ||
      !labels.includes(labels.length)) {
    return JSON.stringify({accepted:false, reason:'pagination incompatible'});
  }
  select.selectedIndex = index;
  select.dispatchEvent(new Event('input', {bubbles:true}));
  select.dispatchEvent(new Event('change', {bubbles:true}));
  return JSON.stringify({accepted:true, page:$page});
})()
''';
}

/// WebView plugins may return an already-decoded object or JSON encoded
/// once/twice. Reject navigation if the page did not acknowledge it.
bool browserTurnAccepted(Object result) {
  dynamic value = result;
  try {
    for (var i = 0; i < 3 && value is String; i++) {
      value = jsonDecode(value);
    }
  } catch (_) {
    return false;
  }
  return value is Map && value['accepted'] == true;
}
