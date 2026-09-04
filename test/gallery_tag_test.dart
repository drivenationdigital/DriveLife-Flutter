import 'package:drivelife/models/gallery_tag.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dedupe rule is the subtle part: a vehicle tag may have entityId 0 when
/// the plate matches nobody's garage, so identity falls back to the plate
/// itself. Get this wrong and the same car can be tagged twice, or two
/// different members collapse into one.
void main() {
  GalleryTag member(int id, String handle) =>
      GalleryTag(kind: TagKind.member, label: handle, entityId: id);

  GalleryTag vehicle(int id, String plate) => GalleryTag(
    kind: TagKind.vehicle,
    label: plate,
    entityId: id,
    registration: plate,
  );

  group('matches', () {
    test('same member id is the same tag, whatever the handle says', () {
      expect(member(7, 'marcus').matches(member(7, 'renamed')), isTrue);
    });

    test('different member ids are different tags', () {
      expect(member(7, 'marcus').matches(member(8, 'marcus')), isFalse);
    });

    test('a member never matches a vehicle', () {
      expect(member(7, 'AB12CDE').matches(vehicle(7, 'AB12CDE')), isFalse);
    });

    test('same garage id is the same vehicle', () {
      expect(vehicle(3, 'AB12CDE').matches(vehicle(3, 'XY99ZZZ')), isTrue);
    });

    test('two unmatched plates dedupe on the plate itself', () {
      // Both have entityId 0, so ids cannot distinguish them.
      expect(vehicle(0, 'AB12CDE').matches(vehicle(0, 'AB12CDE')), isTrue);
      expect(vehicle(0, 'AB12CDE').matches(vehicle(0, 'XY99ZZZ')), isFalse);
    });

    test('plate comparison ignores case', () {
      expect(vehicle(0, 'ab12cde').matches(vehicle(0, 'AB12CDE')), isTrue);
    });

    test('a known vehicle does not collapse into an unmatched plate', () {
      // One side has a real garage id, so ids decide — 3 != 0.
      expect(vehicle(3, 'AB12CDE').matches(vehicle(0, 'AB12CDE')), isFalse);
    });
  });

  group('fromJson', () {
    test('rebuilds a member tag the server sent back', () {
      final tag = GalleryTag.fromJson({
        'entity_type': 'user',
        'entity_id': 7,
        'label': 'marcus',
        'subtitle': 'Marcus Webb',
        'image': 'https://example.test/a.jpg',
      });

      expect(tag.kind, TagKind.member);
      expect(tag.entityId, 7);
      expect(tag.label, 'marcus');
      expect(tag.subtitle, 'Marcus Webb');
      expect(tag.avatarUrl, 'https://example.test/a.jpg');
    });

    test('rebuilds an unmatched plate, id 0 and all', () {
      final tag = GalleryTag.fromJson({
        'entity_type': 'car',
        'entity_id': 0,
        'label': 'AB12CDE',
        'registration': 'AB12CDE',
      });

      expect(tag.kind, TagKind.vehicle);
      expect(tag.entityId, 0);
      expect(tag.registration, 'AB12CDE');
    });

    test('survives a round trip through toJson', () {
      // What the per-photo screen relies on: a saved tag comes back as a tag
      // that can be removed and re-saved without changing meaning.
      final original = vehicle(3, 'AB12CDE');
      final restored = GalleryTag.fromJson({
        'entity_type': 'car',
        'entity_id': 3,
        'label': 'AB12CDE',
        'registration': 'AB12CDE',
      });

      expect(restored.toJson(), original.toJson());
      expect(restored.matches(original), isTrue);
    });

    test('a missing image is empty, not the string "null"', () {
      // Interpolating a null straight into a string is an easy way to end up
      // requesting an image at the URL "null".
      final tag = GalleryTag.fromJson({
        'entity_type': 'user',
        'entity_id': 7,
        'label': 'marcus',
      });

      expect(tag.avatarUrl, isEmpty);
    });
  });

  group('toJson', () {
    test('a member sends no registration', () {
      expect(member(7, 'marcus').toJson(), {
        'entity_type': 'user',
        'entity_id': 7,
      });
    });

    test('a vehicle sends its registration', () {
      expect(vehicle(3, 'AB12CDE').toJson(), {
        'entity_type': 'car',
        'entity_id': 3,
        'registration': 'AB12CDE',
      });
    });

    test('an unmatched plate still sends the registration with id 0', () {
      // This is the row the server keeps so the car can be linked later.
      expect(vehicle(0, 'AB12CDE').toJson(), {
        'entity_type': 'car',
        'entity_id': 0,
        'registration': 'AB12CDE',
      });
    });
  });
}
