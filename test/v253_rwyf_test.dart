import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pazulu_reader/core/anime/rwyf/rwyf_extension.dart';
import 'package:pazulu_reader/core/anime/rwyf/rwyf_room.dart';
import 'package:pazulu_reader/core/anime/rwyf/zip_entry.dart';

// Archive built with Python's zipfile: one stored file, one deflated file.
const _zip = 'UEsDBBQAAAAAAE16aV0wT8duEwAAABMAAAANAAAAbWFuaWZlc3QuanNvbnsidmVyc2lvbiI6IjMuNC4xIn1QSwMEFAAAAAgATXppXWQy5fgbAAAAkAEAABEAAABjb250ZW50X3NjcmlwdC5qc0vOzyvOz0nVy8lP11AqKq9MU9K0Th4VGzAxAFBLAQIUAxQAAAAAAE16aV0wT8duEwAAABMAAAANAAAAAAAAAAAAAACAAQAAAABtYW5pZmVzdC5qc29uUEsBAhQDFAAAAAgATXppXWQy5fgbAAAAkAEAABEAAAAAAAAAAAAAAIABPgAAAGNvbnRlbnRfc2NyaXB0LmpzUEsFBgAAAAACAAIAegAAAIgAAAAAAA==';

void main() {
  test('zipEntry : fichier stocké et fichier compressé (deflate)', () {
    final bytes = base64Decode(_zip);
    expect(utf8.decode(zipEntry(bytes, 'manifest.json')!), '{"version":"3.4.1"}');
    expect(utf8.decode(zipEntry(bytes, 'content_script.js')!), 'console.log("rwyf");' * 20);
    expect(zipEntry(bytes, 'absent.js'), isNull);
    expect(zipEntry(utf8.encode('pas un zip'), 'x'), isNull);
  });

  test('socket.io : paquets lus et écrits', () {
    expect(decodeSocketIoPacket('0{"sid":"a"}').$1, 'open');
    expect(decodeSocketIoPacket('2').$1, 'ping');
    expect(decodeSocketIoPacket('40{"sid":"b"}').$1, 'connected');
    final (kind, ev) = decodeSocketIoPacket('42["join","ROOM1","paused",12.5,2]');
    expect(kind, 'event');
    expect(ev, ['join', 'ROOM1', 'paused', 12.5, 2]);
    expect(encodeSocketIoEvent('update', ['playing', 30]), '42["update","playing",30]');
    final u = socketIoEndpoint({'videoProgress': '0', 'videoState': 'paused', 'room': 'R'});
    expect(u.scheme, 'wss');
    expect(u.host, 'rwyf-sync.onrender.com');
    expect(u.path, '/socket.io/');
    expect(u.queryParameters['EIO'], '4');
    expect(u.queryParameters['transport'], 'websocket');
    expect(u.queryParameters['room'], 'R');
  });

  test('DNS sécurisé : adresse IPv4 après les CNAME, rien si le nom n’existe pas', () {
    const ok = '{"Status":0,"Answer":[{"name":"rt-sync.azurewebsites.net","type":5,"data":"waws.cloudapp.net."},'
        '{"name":"waws.cloudapp.net","type":1,"data":"20.43.1.2"}]}';
    expect(parseDnsJsonAnswer(ok), '20.43.1.2');
    expect(parseDnsJsonAnswer('{"Status":3}'), isNull);
    expect(parseDnsJsonAnswer('{"Status":0,"Answer":[{"type":28,"data":"::1"}]}'), isNull);
  });

  test('liens de soirée identiques à l’extension', () {
    const ep = 'https://www.crunchyroll.com/fr/watch/GABC/slug';
    final link = RwyfRoom.withRoom(ep, 'XYZ');
    expect(link, '$ep?rollTogetherRoom=XYZ');
    expect(RwyfRoom.roomOf(link), 'XYZ');
    expect(RwyfRoom.roomOf(ep), isNull);
  });

  test('page prête + lien d’un pote : demande la position à la page', () async {
    final sent = <Map<String, Object?>>[];
    final room = RwyfRoom(send: (m) async => sent.add(m));
    room.fromPage({'type': 'port_connection'}, 'https://www.crunchyroll.com/watch/G/x?rollTogetherRoom=R1');
    expect(room.pageReady, isTrue);
    expect(sent.single['type'], 'sw2cs_room_connection');
    // Asked twice: only one request.
    room.createRoom();
    expect(sent.length, 1);
    room.dispose();
  });

  test('page prête sans salon : rien n’est envoyé avant « Créer un salon »', () {
    final sent = <Map<String, Object?>>[];
    final room = RwyfRoom(send: (m) async => sent.add(m));
    room.fromPage({'type': 'port_connection'}, 'https://www.crunchyroll.com/watch/G/x');
    expect(sent, isEmpty);
    room.createRoom();
    expect(sent.single['type'], 'sw2cs_room_connection');
    room.dispose();
  });

  test('serveur lu dans l’extension (suit ses mises à jour)', () {
    expect(RwyfExtension.serverIn('const serverUrl = "https://rt-sync.azurewebsites.net";')?.host,
        'rt-sync.azurewebsites.net');
    expect(RwyfExtension.serverIn("var serverUrl='https://sync.example.org'")?.host, 'sync.example.org');
    expect(RwyfExtension.serverIn('const serverUrl = "http://insecure.example"'), isNull);
    expect(RwyfExtension.serverIn('nothing here'), isNull);
    const ext = RwyfExtension(version: '1', contentScript: '');
    expect(ext.syncServer.host, 'rwyf-sync.onrender.com');
    final old = RwyfExtension(version: '3.4.1', contentScript: '',
        server: Uri.parse('https://rt-sync.azurewebsites.net'));
    expect(old.syncServer.host, 'rwyf-sync.onrender.com');
  });

  test('mise à jour : version la plus récente entre Mozilla et GitHub', () {
    final best = RwyfExtension.newest([
      (version: '3.4.1', url: Uri.parse('https://addons.mozilla.org/a.xpi'), source: 'Mozilla'),
      (version: '3.5.0', url: Uri.parse('https://github.com/b.zip'), source: 'GitHub'),
    ]);
    expect(best?.source, 'GitHub');
    final tie = RwyfExtension.newest([
      (version: '3.5.0', url: Uri.parse('https://addons.mozilla.org/a.xpi'), source: 'Mozilla'),
      (version: '3.5.0', url: Uri.parse('https://github.com/b.zip'), source: 'GitHub'),
    ]);
    expect(tie?.source, 'Mozilla');
    expect(RwyfExtension.newest([]), isNull);
  });

  test('release GitHub : paquet Firefox et version du tag', () {
    const body = '{"tag_name":"v3.5.0","draft":false,"prerelease":false,"assets":['
        '{"name":"rolltogether-chrome.zip","browser_download_url":"https://github.com/x/c.zip"},'
        '{"name":"rolltogether-firefox.zip","browser_download_url":"https://github.com/x/f.zip"}]}';
    final rel = RwyfExtension.releaseFromJson(body);
    expect(rel?.version, '3.5.0');
    expect(rel?.url.toString(), 'https://github.com/x/f.zip');
    expect(RwyfExtension.releaseFromJson('{"tag_name":"v1","assets":[]}'), isNull);
    expect(RwyfExtension.releaseFromJson('{"tag_name":"v1","prerelease":true,"assets":[]}'), isNull);
  });

  test('serveur du dépôt (env.json, production, https seulement)', () {
    const env = '{"development":{"SYNC_SERVER":"https://dev.example"},'
        '"production":{"SYNC_SERVER":"https://rwyf-sync.onrender.com"}}';
    expect(RwyfExtension.serverInEnv(env)?.host, 'rwyf-sync.onrender.com');
    expect(RwyfExtension.serverInEnv('{"production":{"SYNC_SERVER":"http://x"}}'), isNull);
    expect(RwyfExtension.serverInEnv('pas du json'), isNull);
  });

  test('injection : seulement sur crunchyroll.com, pont avant l’extension', () {
    const ext = RwyfExtension(version: '3.4.1', contentScript: '/*CS*/');
    final js = ext.injection();
    expect(js, contains(r'(^|\.)crunchyroll\.com$'));
    expect(js.indexOf('__pazuluRwyf'), lessThan(js.indexOf('/*CS*/')));
    expect(js, contains('window.browser'));
  });
}
