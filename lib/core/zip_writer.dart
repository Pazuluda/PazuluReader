import 'dart:convert';
import 'dart:typed_data';

/// Petit fichier ZIP sans compression (« stocké ») : assez pour un rapport
/// de bug de quelques fichiers texte, sans dépendance supplémentaire.
class ZipWriter {
  final List<(String, Uint8List, int)> _files = [];

  void addText(String name, String text) => addBytes(name, Uint8List.fromList(utf8.encode(text)));

  void addBytes(String name, Uint8List data) => _files.add((name, data, crc32(data)));

  static final List<int> _table = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int crc32(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  Uint8List build() {
    final out = BytesBuilder();
    final central = BytesBuilder();
    void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
    void u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    for (final (name, data, crc) in _files) {
      final n = utf8.encode(name);
      final offset = out.length;
      u32(out, 0x04034b50);
      u16(out, 20); // version
      u16(out, 0x0800); // UTF-8 names
      u16(out, 0); // stored
      u16(out, 0);
      u16(out, 0x21); // time / date (1980-01-01)
      u32(out, crc);
      u32(out, data.length);
      u32(out, data.length);
      u16(out, n.length);
      u16(out, 0);
      out.add(n);
      out.add(data);

      u32(central, 0x02014b50);
      u16(central, 20);
      u16(central, 20);
      u16(central, 0x0800);
      u16(central, 0);
      u16(central, 0);
      u16(central, 0x21);
      u32(central, crc);
      u32(central, data.length);
      u32(central, data.length);
      u16(central, n.length);
      u16(central, 0);
      u16(central, 0);
      u16(central, 0);
      u16(central, 0);
      u32(central, 0);
      u32(central, offset);
      central.add(n);
    }
    final cdOffset = out.length;
    final cd = central.toBytes();
    out.add(cd);
    u32(out, 0x06054b50);
    u16(out, 0);
    u16(out, 0);
    u16(out, _files.length);
    u16(out, _files.length);
    u32(out, cd.length);
    u32(out, cdOffset);
    u16(out, 0);
    return out.toBytes();
  }
}
