import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads one file of a ZIP archive (an .xpi is a ZIP) without writing
/// anything to disk. Only « stored » and « deflate » entries.
/// Returns null when the entry is absent or the archive is not readable.
Uint8List? zipEntry(Uint8List zip, String name) {
  final data = ByteData.sublistView(zip);
  // End of central directory: last 22..65 557 bytes.
  var eocd = -1;
  for (var i = zip.length - 22; i >= 0 && i >= zip.length - 65557; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) return null;
  final count = data.getUint16(eocd + 10, Endian.little);
  var p = data.getUint32(eocd + 16, Endian.little);
  for (var n = 0; n < count; n++) {
    if (p + 46 > zip.length || data.getUint32(p, Endian.little) != 0x02014b50) return null;
    final method = data.getUint16(p + 10, Endian.little);
    final compSize = data.getUint32(p + 20, Endian.little);
    final nameLen = data.getUint16(p + 28, Endian.little);
    final extraLen = data.getUint16(p + 30, Endian.little);
    final commentLen = data.getUint16(p + 32, Endian.little);
    final local = data.getUint32(p + 42, Endian.little);
    final entryName = utf8.decode(zip.sublist(p + 46, p + 46 + nameLen), allowMalformed: true);
    if (entryName == name) {
      if (local + 30 > zip.length || data.getUint32(local, Endian.little) != 0x04034b50) return null;
      final lName = data.getUint16(local + 26, Endian.little);
      final lExtra = data.getUint16(local + 28, Endian.little);
      final start = local + 30 + lName + lExtra;
      if (start + compSize > zip.length) return null;
      final raw = zip.sublist(start, start + compSize);
      if (method == 0) return raw;
      if (method == 8) return Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
      return null;
    }
    p += 46 + nameLen + extraLen + commentLen;
  }
  return null;
}
