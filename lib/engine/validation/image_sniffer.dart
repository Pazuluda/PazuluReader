import 'dart:convert';
import 'dart:typed_data';

/// What the first bytes of a "page" really are.
enum PayloadKind { image, html, json, text, empty, unknown }

/// Pure-Dart inspection of the first bytes of a response. Reads magic numbers
/// and image headers only: no full decode is needed to reject an HTML error
/// page served with an image URL, a 1x1 tracker or a loading spinner.
class ImageSniff {
  const ImageSniff({
    required this.kind,
    this.format,
    this.width,
    this.height,
    this.animated = false,
    this.text,
  });

  final PayloadKind kind;

  /// jpeg / png / webp / gif / avif / bmp.
  final String? format;
  final int? width;
  final int? height;
  final bool animated;

  /// Decoded leading text for html/json/text payloads (bounded).
  final String? text;

  bool get isImage => kind == PayloadKind.image;
  bool get hasDimensions => width != null && height != null;

  static ImageSniff inspect(Uint8List bytes, {String? contentType}) {
    if (bytes.isEmpty) return const ImageSniff(kind: PayloadKind.empty);
    final b = bytes;
    // JPEG
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      final dims = _jpegSize(b);
      return ImageSniff(kind: PayloadKind.image, format: 'jpeg',
          width: dims?.$1, height: dims?.$2);
    }
    // PNG
    if (b.length >= 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E &&
        b[3] == 0x47) {
      final view = ByteData.sublistView(b);
      final animated = _contains(b, ascii.encode('acTL'), limit: 4096);
      return ImageSniff(kind: PayloadKind.image, format: 'png',
          width: view.getUint32(16), height: view.getUint32(20), animated: animated);
    }
    // GIF
    if (b.length >= 10 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      final view = ByteData.sublistView(b);
      return ImageSniff(kind: PayloadKind.image, format: 'gif',
          width: view.getUint16(6, Endian.little),
          height: view.getUint16(8, Endian.little));
    }
    // WEBP: RIFF....WEBP
    if (b.length >= 30 && _ascii(b, 0, 4) == 'RIFF' && _ascii(b, 8, 4) == 'WEBP') {
      final dims = _webpSize(b);
      return ImageSniff(kind: PayloadKind.image, format: 'webp',
          width: dims?.$1, height: dims?.$2, animated: dims?.$3 ?? false);
    }
    // AVIF / HEIF: ....ftypavif
    if (b.length >= 12 && _ascii(b, 4, 4) == 'ftyp') {
      final brand = _ascii(b, 8, 4);
      if (brand == 'avif' || brand == 'avis' || brand == 'heic' || brand == 'mif1') {
        final dims = _ispeSize(b);
        return ImageSniff(kind: PayloadKind.image, format: 'avif',
            width: dims?.$1, height: dims?.$2);
      }
    }
    // BMP
    if (b.length >= 26 && b[0] == 0x42 && b[1] == 0x4D) {
      final view = ByteData.sublistView(b);
      return ImageSniff(kind: PayloadKind.image, format: 'bmp',
          width: view.getInt32(18, Endian.little).abs(),
          height: view.getInt32(22, Endian.little).abs());
    }
    // Text-like payloads.
    final head = utf8.decode(b.length > 16384 ? b.sublist(0, 16384) : b,
        allowMalformed: true);
    final trimmed = head.trimLeft().toLowerCase();
    if (trimmed.startsWith('<!doctype html') || trimmed.startsWith('<html') ||
        trimmed.startsWith('<head') || trimmed.startsWith('<body') ||
        (trimmed.startsWith('<') && trimmed.contains('<html'))) {
      return ImageSniff(kind: PayloadKind.html, text: head);
    }
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return ImageSniff(kind: PayloadKind.json, text: head);
    }
    if (trimmed.startsWith('<svg') || trimmed.startsWith('<?xml')) {
      // SVG is never a manga page here (placeholders, spinners, logos).
      return ImageSniff(kind: PayloadKind.text, format: 'svg', text: head);
    }
    final printable = head.runes.take(512).where((r) =>
        r == 9 || r == 10 || r == 13 || (r >= 32 && r != 0xFFFD)).length;
    final sample = head.runes.take(512).length;
    if (sample > 0 && printable / sample > 0.95) {
      return ImageSniff(kind: PayloadKind.text, text: head);
    }
    final type = contentType?.toLowerCase() ?? '';
    if (type.startsWith('text/html')) return ImageSniff(kind: PayloadKind.html, text: head);
    return const ImageSniff(kind: PayloadKind.unknown);
  }

  static String _ascii(Uint8List b, int start, int length) {
    if (start + length > b.length) return '';
    return String.fromCharCodes(b.sublist(start, start + length));
  }

  static bool _contains(Uint8List b, List<int> needle, {int limit = 4096}) {
    final end = b.length < limit ? b.length : limit;
    outer:
    for (var i = 0; i + needle.length <= end; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (b[i + j] != needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  /// Walks JPEG markers until a SOFn frame header.
  static (int, int)? _jpegSize(Uint8List b) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xFF) {
        i++;
        continue;
      }
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final length = (b[i + 2] << 8) | b[i + 3];
      final isSof = marker >= 0xC0 && marker <= 0xCF &&
          marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
      if (isSof) {
        final height = (b[i + 5] << 8) | b[i + 6];
        final width = (b[i + 7] << 8) | b[i + 8];
        return (width, height);
      }
      if (length < 2) return null;
      i += 2 + length;
    }
    return null;
  }

  static (int, int, bool)? _webpSize(Uint8List b) {
    final chunk = _ascii(b, 12, 4);
    if (chunk == 'VP8X' && b.length >= 30) {
      final animated = (b[20] & 0x02) != 0;
      final w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
      final h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
      return (w, h, animated);
    }
    if (chunk == 'VP8 ' && b.length >= 30) {
      final w = (b[26] | (b[27] << 8)) & 0x3FFF;
      final h = (b[28] | (b[29] << 8)) & 0x3FFF;
      return (w, h, false);
    }
    if (chunk == 'VP8L' && b.length >= 25) {
      final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      final w = (bits & 0x3FFF) + 1;
      final h = ((bits >> 14) & 0x3FFF) + 1;
      return (w, h, false);
    }
    return null;
  }

  /// AVIF/HEIF: dimensions live in the 'ispe' property box.
  static (int, int)? _ispeSize(Uint8List b) {
    final needle = ascii.encode('ispe');
    final end = b.length < 65536 ? b.length : 65536;
    for (var i = 0; i + 16 <= end; i++) {
      if (b[i] == needle[0] && b[i + 1] == needle[1] && b[i + 2] == needle[2] &&
          b[i + 3] == needle[3]) {
        final view = ByteData.sublistView(b);
        // box: size(4) 'ispe'(4) version/flags(4) width(4) height(4)
        if (i + 12 <= b.length) {
          return (view.getUint32(i + 8), view.getUint32(i + 12));
        }
      }
    }
    return null;
  }
}
