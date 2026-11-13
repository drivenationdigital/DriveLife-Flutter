import 'dart:io';
import 'dart:typed_data';

import 'package:drivelife/utils/mp4_probe.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading a video's GPS tag.
///
/// This exists because photo_manager's latlngAsync() reads MediaStore
/// columns Android 10 removed, so every video came back with no
/// location while the phone's own gallery put it on a map. A photo
/// survives that through its EXIF; a video needs its own file read.
void main() {
  // ── Building MP4 atoms by hand ──────────────────────────────────
  //
  // Synthetic rather than a fixture file: a real phone video is
  // hundreds of megabytes, and the shapes worth testing — moov at the
  // end, a 64-bit size, a truncated atom — are easier to write than to
  // find.

  Uint8List atom(String type, List<int> payload) {
    final out = BytesBuilder();

    out.add(_u32(payload.length + 8));
    out.add(type.codeUnits);
    out.add(payload);

    return out.toBytes();
  }

  /// A ©xyz payload: 2-byte length, 2-byte language, then the string.
  Uint8List xyz(String iso) {
    final text = iso.codeUnits;
    final out = BytesBuilder();

    out.add(_u16(text.length));
    out.add(_u16(0x15C7)); // language, which nothing reads
    out.add(text);

    return atom('©xyz', out.toBytes());
  }

  Future<File> fileOf(List<int> bytes) async {
    final dir = await Directory.systemTemp.createTemp('mp4probe');
    final file = File('${dir.path}/clip.mp4');

    await file.writeAsBytes(bytes);

    return file;
  }

  group('parsing the position string', () {
    test('the common shape', () {
      final found = Mp4Probe.parseIso6709('+53.7909-1.2069/');

      expect(found?.latitude, closeTo(53.7909, 0.0001));
      expect(found?.longitude, closeTo(-1.2069, 0.0001));
    });

    test('an altitude after it is ignored', () {
      // Where it was filmed is the question; how high up is not.
      final found = Mp4Probe.parseIso6709('+53.7909-1.2069+350.000/');

      expect(found?.latitude, closeTo(53.7909, 0.0001));
      expect(found?.longitude, closeTo(-1.2069, 0.0001));
    });

    test('a missing trailing solidus is tolerated', () {
      expect(Mp4Probe.parseIso6709('+52.6054-1.0333'), isNotNull);
    });

    test('both hemispheres', () {
      final found = Mp4Probe.parseIso6709('-33.8688+151.2093/');

      expect(found?.latitude, closeTo(-33.8688, 0.0001));
      expect(found?.longitude, closeTo(151.2093, 0.0001));
    });

    test('the sign is what separates the two numbers', () {
      // Without a mandatory sign on the longitude there is no way to
      // tell where the latitude ends.
      expect(Mp4Probe.parseIso6709('53.7909-1.2069/'), isNull);
    });

    test('0,0 is refused', () {
      // The Atlantic, and what an unset tag looks like. Same rule the
      // gallery read uses.
      expect(Mp4Probe.parseIso6709('+0.0000+0.0000/'), isNull);
    });

    test('out of range is refused rather than clamped', () {
      expect(Mp4Probe.parseIso6709('+99.0000-1.2069/'), isNull);
      expect(Mp4Probe.parseIso6709('+53.7909-200.0000/'), isNull);
    });

    test('rubbish is null rather than an exception', () {
      expect(Mp4Probe.parseIso6709(''), isNull);
      expect(Mp4Probe.parseIso6709('not a position'), isNull);
      expect(Mp4Probe.parseIso6709('+/'), isNull);
    });
  });

  group('walking the file', () {
    test('finds it in moov/udta, where Android writes it', () async {
      final file = await fileOf([
        ...atom('ftyp', List.filled(16, 0)),
        ...atom('moov', [
          ...atom('udta', xyz('+53.7909-1.2069/')),
        ]),
      ]);

      final found = await Mp4Probe.locationOf(file);

      expect(found?.latitude, closeTo(53.7909, 0.0001));
      expect(found?.longitude, closeTo(-1.2069, 0.0001));
    });

    test('finds it with moov at the END of the file', () async {
      // The case that matters. A video not written for streaming puts
      // moov last, which is why this seeks rather than reading a
      // prefix — a 200MB clip would otherwise need reading in full.
      final file = await fileOf([
        ...atom('ftyp', List.filled(16, 0)),
        ...atom('mdat', List.filled(4096, 7)),
        ...atom('moov', [
          ...atom('udta', xyz('+52.6054-1.0333/')),
        ]),
      ]);

      final found = await Mp4Probe.locationOf(file);

      expect(found?.latitude, closeTo(52.6054, 0.0001));
    });

    test('finds it nested under meta/ilst, as iOS writes it', () async {
      final file = await fileOf([
        ...atom('ftyp', List.filled(8, 0)),
        ...atom('moov', [
          ...atom('meta', [
            // A full box: four bytes of version and flags first.
            0, 0, 0, 0,
            ...atom('ilst', xyz('-33.8688+151.2093/')),
          ]),
        ]),
      ]);

      final found = await Mp4Probe.locationOf(file);

      expect(found?.longitude, closeTo(151.2093, 0.0001));
    });

    test('handles a 64-bit atom size', () async {
      // size == 1 means the real size is in the eight bytes after the
      // type. A large mdat is the usual reason.
      final payload = List.filled(32, 0);

      final big = BytesBuilder()
        ..add(_u32(1))
        ..add('mdat'.codeUnits)
        ..add(_u64(payload.length + 16))
        ..add(payload);

      final file = await fileOf([
        ...atom('ftyp', List.filled(8, 0)),
        ...big.toBytes(),
        ...atom('moov', [
          ...atom('udta', xyz('+53.7909-1.2069/')),
        ]),
      ]);

      expect(await Mp4Probe.locationOf(file), isNotNull);
    });

    test('reads a 3GPP loci box, longitude first', () async {
      // loci puts LONGITUDE before latitude, the reverse of ISO 6709.
      // Reading them in the wrong order lands you in the sea off
      // Somalia, which is the classic symptom of this box.
      int fixed(double v) => (v * 65536).round();

      final body = BytesBuilder()
        ..add([0, 0, 0, 0]) // version + flags
        ..add(_u16(0x55C4)) // language
        ..add('The Motorist'.codeUnits)
        ..add([0]) // name terminator
        ..add([0]) // role
        ..add(_i32(fixed(-1.2069))) // longitude FIRST
        ..add(_i32(fixed(53.7909)));

      final file = await fileOf([
        ...atom('ftyp', List.filled(8, 0)),
        ...atom('moov', [...atom('udta', atom('loci', body.toBytes()))]),
      ]);

      final found = await Mp4Probe.locationOf(file);

      expect(found?.latitude, closeTo(53.7909, 0.001));
      expect(found?.longitude, closeTo(-1.2069, 0.001));
    });

    test('finds a position stored under QuickTime keys', () async {
      // The keys scheme names ilst entries by NUMBER, with the real key
      // in a separate table — so there is no atom called ©xyz to find,
      // even though the string is sitting there in plain ASCII. The
      // text scan is what catches that.
      final value = BytesBuilder()
        ..add(_u32(28))
        ..add('data'.codeUnits)
        ..add([0, 0, 0, 1, 0, 0, 0, 0])
        ..add('+52.6054-1.0333/'.codeUnits);

      final numbered = BytesBuilder()
        ..add(_u32(value.length + 8))
        ..add([0, 0, 0, 1]) // the entry's "name" is an index
        ..add(value.toBytes());

      final file = await fileOf([
        ...atom('ftyp', List.filled(8, 0)),
        ...atom('moov', [
          ...atom('meta', [0, 0, 0, 0, ...atom('ilst', numbered.toBytes())]),
        ]),
      ]);

      final found = await Mp4Probe.locationOf(file);

      expect(found?.latitude, closeTo(52.6054, 0.001));
    });

    test('a video with no tag is null, not an error', () async {
      final file = await fileOf([
        ...atom('ftyp', List.filled(16, 0)),
        ...atom('moov', [
          ...atom('udta', atom('name', 'clip'.codeUnits)),
        ]),
      ]);

      expect(await Mp4Probe.locationOf(file), isNull);
    });

    test('a truncated atom does not hang or throw', () async {
      // A size claiming more than the file holds. Seen on a file still
      // being written, or one a transfer cut short.
      final file = await fileOf([
        ..._u32(9999),
        ...'moov'.codeUnits,
        ...List.filled(16, 0),
      ]);

      expect(await Mp4Probe.locationOf(file), isNull);
    });

    test('an atom claiming zero size does not loop forever', () async {
      // size 0 means "to the end of the file", which is legal for the
      // last atom and a trap if read as "advance by nothing".
      final file = await fileOf([
        ..._u32(0),
        ...'free'.codeUnits,
        ...List.filled(64, 0),
      ]);

      expect(await Mp4Probe.locationOf(file), isNull);
    });

    test('a file that is not an MP4 at all is null', () async {
      final file = await fileOf(List.generate(512, (i) => i % 256));

      expect(await Mp4Probe.locationOf(file), isNull);
    });

    test('an empty file is null', () async {
      expect(await Mp4Probe.locationOf(await fileOf(const [])), isNull);
    });
  });
}

List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

List<int> _u32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

List<int> _u64(int v) => [...List.filled(4, 0), ..._u32(v)];

List<int> _i32(int v) => _u32(v & 0xFFFFFFFF);
