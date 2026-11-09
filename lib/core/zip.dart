import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

/// Lecture/écriture minimale d'archives ZIP (format CBZ), sans dépendance.
/// Écriture : méthode « stockée » (les images sont déjà compressées).
/// Lecture : méthodes stockée et « deflate ».

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    t[n] = c;
  }
  return t;
}();

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

class ZipEntry {
  const ZipEntry(this.name, this.data);

  final String name;
  final Uint8List data;
}

Uint8List writeZip(List<ZipEntry> entries) {
  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var offset = 0;

  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  for (final e in entries) {
    final name = Uint8List.fromList(e.name.codeUnits);
    final crc = crc32(e.data);
    final local = BytesBuilder(copy: false);
    u32(local, 0x04034b50);
    u16(local, 20); // version
    u16(local, 0); // flags
    u16(local, 0); // stockée
    u16(local, 0); // heure
    u16(local, 0x21); // date (1980-01-01)
    u32(local, crc);
    u32(local, e.data.length);
    u32(local, e.data.length);
    u16(local, name.length);
    u16(local, 0);
    local.add(name);
    final header = local.takeBytes();
    out.add(header);
    out.add(e.data);

    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0x21);
    u32(central, crc);
    u32(central, e.data.length);
    u32(central, e.data.length);
    u16(central, name.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, 0);
    u32(central, offset);
    central.add(name);

    offset += header.length + e.data.length;
  }

  final cd = central.takeBytes();
  out.add(cd);
  final end = BytesBuilder(copy: false);
  u32(end, 0x06054b50);
  u16(end, 0);
  u16(end, 0);
  u16(end, entries.length);
  u16(end, entries.length);
  u32(end, cd.length);
  u32(end, offset);
  u16(end, 0);
  out.add(end.takeBytes());
  return out.takeBytes();
}

/// Lit les fichiers d'une archive ZIP à partir de son répertoire central.
List<ZipEntry> readZip(Uint8List bytes) {
  if (bytes.length < 22) throw const FormatException('Archive ZIP trop courte.');
  final view = ByteData.sublistView(bytes);
  int u16(int o) => view.getUint16(o, Endian.little);
  int u32(int o) => view.getUint32(o, Endian.little);

  var eocd = -1;
  for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
    if (u32(i) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const FormatException('Archive ZIP invalide.');

  final count = u16(eocd + 10);
  if (count > 1000) throw const FormatException('Archive ZIP trop fournie.');
  var p = u32(eocd + 16);
  var expandedBytes = 0;
  final entries = <ZipEntry>[];
  for (var i = 0; i < count; i++) {
    if (p < 0 || p + 46 > bytes.length || u32(p) != 0x02014b50) {
      throw const FormatException('Archive ZIP endommagée.');
    }
    final method = u16(p + 10);
    final compSize = u32(p + 20);
    final plainSize = u32(p + 24);
    // Reject decompression bombs before calling the inflate codec.
    if (plainSize > 40 * 1024 * 1024 ||
        expandedBytes + plainSize > 450 * 1024 * 1024) {
      throw const FormatException('Archive ZIP trop volumineuse apres decompression.');
    }
    expandedBytes += plainSize;
    final nameLen = u16(p + 28);
    final extraLen = u16(p + 30);
    final commentLen = u16(p + 32);
    final localOffset = u32(p + 42);
    if (p + 46 + nameLen + extraLen + commentLen > bytes.length ||
        localOffset + 30 > bytes.length) {
      throw const FormatException('Archive ZIP tronquee.');
    }
    final name = String.fromCharCodes(bytes.sublist(p + 46, p + 46 + nameLen));
    p += 46 + nameLen + extraLen + commentLen;

    final lNameLen = u16(localOffset + 26);
    final lExtraLen = u16(localOffset + 28);
    final start = localOffset + 30 + lNameLen + lExtraLen;
    if (start < 0 || start + compSize > bytes.length) {
      throw const FormatException('Donnees ZIP tronquees.');
    }
    final raw = Uint8List.sublistView(bytes, start, start + compSize);
    final Uint8List data;
    if (method == 0) {
      data = Uint8List.fromList(raw);
    } else if (method == 8) {
      data = Uint8List.fromList(ZLibCodec(raw: true).decode(raw));
    } else {
      continue;
    }
    if (data.length != plainSize) {
      throw const FormatException('Taille de fichier ZIP incoherente.');
    }
    if (!name.endsWith('/')) entries.add(ZipEntry(name, data));
  }
  return entries;
}
