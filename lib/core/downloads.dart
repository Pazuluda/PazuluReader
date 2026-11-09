import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import 'chapter_key.dart';
import 'chapter_identity.dart';
import 'models.dart';
import 'source.dart';
import 'zip.dart';

/// Un chapitre enregistré hors ligne (fichier .cbz).
class DownloadRecord {
  DownloadRecord({
    required this.chapterId,
    required this.sourceId,
    required this.workId,
    required this.keyId,
    required this.lang,
    required this.group,
    required this.path,
    required this.pages,
    required this.bytes,
    required this.savedAt,
    this.title,
  });

  final String chapterId;
  final String sourceId;
  final String workId;
  final String keyId;
  final String lang;
  final String group;
  final String path;
  final int pages;
  final int bytes;
  final DateTime savedAt;
  final String? title;

  SourceChapter toChapter() => SourceChapter(
        sourceId: sourceId,
        chapterId: chapterId,
        key: ChapterKey.parse(keyId),
        lang: lang,
        group: group,
        title: title,
        pages: pages,
        // The moment the copy was saved is NOT a release date (2.3.20: a
        // copy saved at 23:59 showed « Sorti il y a 7 h » and « NOUVEAU »).
      );

  Map<String, dynamic> toJson() => {
        'chapterId': chapterId,
        'sourceId': sourceId,
        'workId': workId,
        'keyId': keyId,
        'lang': lang,
        'group': group,
        'path': path,
        'pages': pages,
        'bytes': bytes,
        'savedAt': savedAt.toIso8601String(),
        'title': title,
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> j) => DownloadRecord(
        chapterId: j['chapterId'] as String,
        sourceId: j['sourceId'] as String,
        workId: j['workId'] as String,
        keyId: j['keyId'] as String,
        lang: (j['lang'] as String?) ?? 'en',
        group: (j['group'] as String?) ?? '',
        path: j['path'] as String,
        pages: (j['pages'] as int?) ?? 0,
        bytes: (j['bytes'] as int?) ?? 0,
        savedAt: DateTime.tryParse((j['savedAt'] as String?) ?? '') ?? DateTime.now(),
        title: j['title'] as String?,
      );
}

/// Reject HTML challenge / error pages even when a server replies HTTP 200.
/// An image mime-type is required or a recognized binary image signature.
bool _looksLikeImage(Uint8List bytes, String? type) {
  if (bytes.length < 8) return false;
  if (type != null && type.toLowerCase().startsWith('text/')) return false;
  final jpg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  final png = bytes[0] == 0x89 && bytes[1] == 0x50 &&
      bytes[2] == 0x4E && bytes[3] == 0x47;
  final gif = bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
  final webp = bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
  final avif = bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(4, 12)).startsWith('ftypavif');
  final bmp = bytes[0] == 0x42 && bytes[1] == 0x4D;
  return jpg || png || gif || webp || avif || bmp;
}

String _imageExt(Uri url, String? type) {
  final path = url.pathSegments.isEmpty ? '' : url.pathSegments.last.toLowerCase();
  final ext = path.contains('.') ? path.split('.').last : '';
  if (const {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'avif'}.contains(ext)) {
    return ext;
  }
  final mime = (type ?? '').toLowerCase();
  if (mime.contains('png')) return 'png';
  if (mime.contains('webp')) return 'webp';
  if (mime.contains('gif')) return 'gif';
  if (mime.contains('avif')) return 'avif';
  if (mime.contains('bmp')) return 'bmp';
  return 'jpg';
}

/// Téléchargements hors ligne : un .cbz par chapitre + un index JSON.
class DownloadStore {
  DownloadStore(Directory base) : dir = Directory('${base.path}${Platform.pathSeparator}hors-ligne');

  final Directory dir;
  final Map<String, DownloadRecord> _records = {};

  File get _index => File('${dir.path}${Platform.pathSeparator}index.json');

  Iterable<DownloadRecord> get all => _records.values;

  int get totalBytes => _records.values.fold(0, (s, r) => s + r.bytes);

  DownloadRecord? byChapter(String chapterId) => _records[chapterId];

  List<DownloadRecord> forWork(String workId) =>
      _records.values.where((r) => r.workId == workId).toList();

  Future<void> load() async {
    if (!await _index.exists()) return;
    try {
      final json = jsonDecode(await _index.readAsString());
      if (json is! List) return;
      for (final e in json) {
        if (e is! Map) continue;
        final r = DownloadRecord.fromJson(e.cast<String, dynamic>());
        if (await File(r.path).exists()) _records[r.chapterId] = r;
      }
    } catch (_) {
      // Index illisible : les fichiers restent sur le disque.
    }
  }

  Future<void>? _indexWrite;
  bool _indexDirty = false;

  /// One write at a time (several deletions at once used to race on the
  /// same tmp file: « Cannot delete file index.json »); the last state is
  /// always written.
  Future<void> _saveIndex() async {
    _indexDirty = true;
    final running = _indexWrite;
    if (running != null) return running;
    final job = () async {
      while (_indexDirty) {
        _indexDirty = false;
        if (!await dir.exists()) await dir.create(recursive: true);
        final tmp = File('${_index.path}.tmp');
        await tmp.writeAsString(
            jsonEncode(_records.values.map((r) => r.toJson()).toList()), flush: true);
        if (await _index.exists()) await _index.delete();
        await tmp.rename(_index.path);
      }
    }();
    _indexWrite = job;
    try {
      await job;
    } finally {
      _indexWrite = null;
    }
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  /// Télécharge toutes les pages et écrit le .cbz.
  Future<DownloadRecord> download({
    required WorkInfo work,
    required SourceChapter chapter,
    required ContentSource source,
    required void Function(double progress) onProgress,
    http.Client? client,
  }) async {
    if (chapter.isExternal) {
      throw const SourceException('Les chapitres des sites officiels ne se téléchargent pas.');
    }
    final pages = await source.getPages(chapter);
    if (pages.isEmpty || pages.length > 300) {
      throw const SourceException('Chapitre vide ou trop grand pour le cache automatique.');
    }
    final c = client ?? http.Client();
    final entries = <ZipEntry>[];
    var totalBytes = 0;
    try {
      for (var i = 0; i < pages.length; i++) {
        Uint8List? data;
        var extension = 'jpg';
        for (final url in [
          pages[i].url,
          if (pages[i].fallbackUrl != null) pages[i].fallbackUrl!,
        ]) {
          final address = Uri.tryParse(url);
          final remoteHttps = address != null && address.scheme == 'https' &&
              address.host.isNotEmpty && !address.hasPort &&
              address.host != 'localhost' && !address.host.endsWith('.local');
          if (address == null || address.userInfo.isNotEmpty ||
              !remoteHttps) continue;
          try {
            final res = await c.get(address, headers: source.imageHeaders)
                .timeout(const Duration(seconds: 30));
            final bytes = res.bodyBytes;
            if (res.statusCode == 200 &&
                bytes.isNotEmpty && bytes.length <= 20 * 1024 * 1024 &&
                _looksLikeImage(bytes, res.headers['content-type'])) {
              data = bytes;
              extension = _imageExt(address, res.headers['content-type']);
              break;
            }
          } catch (_) {
            // Try the reduced-quality URL supplied by the source, if any.
          }
        }
        if (data == null) {
          throw SourceException('Image ${i + 1} non disponible : '
              'aucune page valide ne peut etre ajoutee au CBZ.');
        }
        totalBytes += data.length;
        if (totalBytes > 220 * 1024 * 1024) {
          throw const SourceException('Chapitre trop volumineux pour le cache (220 Mo).');
        }
        final name = '${(i + 1).toString().padLeft(4, '0')}.$extension';
        entries.add(ZipEntry(name, data));
        onProgress((i + 1) / pages.length);
      }
    } finally {
      if (client == null) c.close();
    }

    final workDir = Directory('${dir.path}${Platform.pathSeparator}${_safe(work.title)}');
    if (!await workDir.exists()) await workDir.create(recursive: true);
    // Stable per-chapter filename prevents two sources with the same group
    // and chapter number from overwriting one another.
    final hash = sha256.convert(utf8.encode('${chapter.sourceId}:${chapter.chapterId}'))
        .toString().substring(0, 16);
    final file = File(
      '${workDir.path}${Platform.pathSeparator}'
      '${_safe('${chapter.key.longLabel} ${chapter.lang.toUpperCase()} ${chapter.sourceId}')}_$hash.cbz',
    );
    final zip = writeZip(entries);
    await file.writeAsBytes(zip, flush: true);

    final record = DownloadRecord(
      chapterId: chapter.chapterId,
      sourceId: chapter.sourceId,
      workId: work.id,
      keyId: chapter.key.id,
      lang: chapter.lang,
      group: chapter.group,
      title: chapter.title,
      path: file.path,
      pages: entries.length,
      bytes: zip.length,
      savedAt: DateTime.now(),
    );
    _records[chapter.chapterId] = record;
    await _saveIndex();
    return record;
  }

  /// Lie des archives a une œuvre EXISTANTE. Aucun nouveau livre n'est cree,
  /// et la progression reste indexee par la cle canonique, toutes sources
  /// confondues. Les originaux sont conserves sur l'appareil.
  Future<int> importIntoWork({
    required WorkInfo work,
    required List<String> paths,
    required String language,
    String sourceLabel = 'Archive personnelle',
    String? singleChapterNumber,
  }) async {
    if (language != 'fr' && language != 'en') {
      throw const FormatException('Choisir FR ou EN.');
    }
    if (paths.isEmpty) return 0;
    if (paths.length > 100) {
      throw const FormatException('Import limite a 100 archives a la fois.');
    }
    // Validate everything before writing anything (avoids partial batches
    // when an archive has no identifiable chapter or contains no pictures).
    final prepared = <(String, String, Uint8List, int, String)>[];
    for (final path in paths) {
      final input = File(path);
      final name = path.split(RegExp(r'[\\/]')).last;
      if (!RegExp(r'\.(cbz|zip)$', caseSensitive: false).hasMatch(name)) {
        throw FormatException('Fichier non CBZ/ZIP : $name');
      }
      if (await input.length() > 220 * 1024 * 1024) {
        throw FormatException('Archive trop volumineuse : $name');
      }
      final key = singleChapterNumber != null && paths.length == 1
          ? ChapterKey.parse(singleChapterNumber)
          : ChapterIdentity.detect(title: name);
      if (key == null || key.isSpecial) {
        throw FormatException('Numero inconnu pour $name. Renomme en "Chapitre 12.cbz" '
          'ou saisis le numero pour un fichier unique.');
      }
      final bytes = await input.readAsBytes();
      final entries = readZip(bytes).where((e) =>
          RegExp(r'\.(jpg|jpeg|png|webp|gif|bmp)$', caseSensitive: false)
              .hasMatch(e.name) && e.data.isNotEmpty).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (entries.isEmpty || entries.length > 300) {
        throw FormatException('Nombre de pages invalide dans $name.');
      }
      // Normalized CBZ discards arbitrary paths, scripts and non-images.
      final normalized = writeZip([
        for (var i = 0; i < entries.length; i++)
          ZipEntry('${(i + 1).toString().padLeft(4, '0')}.${entries[i].name.split('.').last.toLowerCase()}',
              entries[i].data),
      ]);
      final digest = sha256.convert(normalized).toString().substring(0, 16);
      prepared.add((key.id, digest, normalized, entries.length, name));
    }
    final folder = Directory('${dir.path}${Platform.pathSeparator}par-oeuvre'
        '${Platform.pathSeparator}${_safe(work.id)}');
    await folder.create(recursive: true);
    for (final (keyId, digest, bytes, pageCount, filename) in prepared) {
      final id = 'local:${work.id}:$language:$keyId:$digest';
      final file = File('${folder.path}${Platform.pathSeparator}'
          '${_safe(keyId)}-$language-$digest.cbz');
      if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
      _records[id] = DownloadRecord(
        chapterId: id, sourceId: 'local', workId: work.id,
        keyId: keyId, lang: language, group: sourceLabel,
        title: filename, path: file.path, pages: pageCount,
        bytes: bytes.length, savedAt: DateTime.now(),
      );
    }
    await _saveIndex();
    return prepared.length;
  }

  /// Importe des fichiers .cbz / .zip déjà présents sur l'appareil.
  /// Les fichiers d'un même dossier forment une même œuvre ; le numéro de
  /// chapitre est lu dans le nom du fichier. Retourne les œuvres créées.
  Future<List<WorkInfo>> importLocal(List<String> paths) async {
    final byTitle = <String, List<String>>{};
    for (final path in paths) {
      final parts = path.split(RegExp(r'[\\/]'));
      final file = parts.last;
      final folder = parts.length > 1 ? parts[parts.length - 2] : '';
      final stem = file.replaceAll(RegExp(r'\.(cbz|zip)$', caseSensitive: false), '');
      final cleaned = stem.replaceAll(RegExp(r'([ _.-]*(ch(apitre|apter)?|ep(isode)?|vol(ume)?)?[ _.-]*\d+([.,]\d+)?)+$', caseSensitive: false), '').trim();
      final title = paths.length > 1 && folder.isNotEmpty ? folder : (cleaned.isEmpty ? stem : cleaned);
      byTitle.putIfAbsent(title, () => []).add(path);
    }

    final works = <WorkInfo>[];
    for (final entry in byTitle.entries) {
      final title = entry.key;
      final workId = 'local:${_safe(title).toLowerCase()}';
      final workDir = Directory('${dir.path}${Platform.pathSeparator}locaux${Platform.pathSeparator}${_safe(title)}');
      if (!await workDir.exists()) await workDir.create(recursive: true);
      String? cover;
      for (final src in entry.value) {
        final name = src.split(RegExp(r'[\\/]')).last;
        final numbers = RegExp(r'\d+(?:[.,]\d+)?').allMatches(name).map((m) => m.group(0)!).toList();
        final key = ChapterKey.parse(numbers.isEmpty ? null : numbers.last);
        final bytes = await File(src).readAsBytes();
        final pages = readZip(bytes)..sort((a, b) => a.name.compareTo(b.name));
        if (pages.isEmpty) continue;
        final target = File('${workDir.path}${Platform.pathSeparator}${_safe(name)}');
        await target.writeAsBytes(bytes, flush: true);
        if (cover == null) {
          final c = File('${workDir.path}${Platform.pathSeparator}couverture.img');
          await c.writeAsBytes(pages.first.data, flush: true);
          cover = Uri.file(c.path).toString();
        }
        final id = '$workId:${key.id}';
        _records[id] = DownloadRecord(
          chapterId: id,
          sourceId: 'local',
          workId: workId,
          keyId: key.id,
          lang: 'local',
          group: 'Fichier local',
          path: target.path,
          pages: pages.length,
          bytes: bytes.length,
          savedAt: DateTime.now(),
        );
      }
      works.add(WorkInfo(id: workId, title: title, coverUrl: cover, type: ContentType.other));
    }
    await _saveIndex();
    return works;
  }

  Future<List<Uint8List>> readPages(DownloadRecord r) async {
    final entries = readZip(await File(r.path).readAsBytes())
      ..sort((a, b) => a.name.compareTo(b.name));
    return [for (final e in entries) e.data];
  }

  Future<void> delete(String chapterId) async {
    final r = _records.remove(chapterId);
    if (r == null) return;
    try {
      await File(r.path).delete();
    } catch (_) {}
    await _saveIndex();
  }
}
