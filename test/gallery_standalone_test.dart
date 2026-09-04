import 'dart:io';

import 'package:drivelife/providers/gallery_upload_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// A gallery is its own entity: tagging an event or venue is optional.
///
/// [GalleryUploadBatch.hasEntity] is what the register call branches on to
/// decide whether to send entity_type/entity_id at all, so getting it wrong
/// either drops a real tag or sends entity_id 0 and 404s the upload.
void main() {
  GalleryUploadBatch batch({
    required String eventId,
    required String entityType,
  }) {
    return GalleryUploadBatch(
      id: 'b1',
      eventId: eventId,
      eventTitle: 'Title',
      entityType: entityType,
      items: [GalleryUploadItem(id: 'i1', file: File('a.jpg'))],
    );
  }

  group('hasEntity', () {
    test('is true for a gallery tagged to an event', () {
      expect(batch(eventId: '12345', entityType: 'event').hasEntity, isTrue);
    });

    test('is true for a gallery tagged to a venue', () {
      expect(batch(eventId: '999', entityType: 'venue').hasEntity, isTrue);
    });

    test('is false for a standalone gallery', () {
      expect(batch(eventId: '', entityType: 'none').hasEntity, isFalse);
    });

    test('is false when the type says none despite a stray id', () {
      // Defends the register call: 'none' must never send an entity, or the
      // server would look up a post type that cannot match and 404.
      expect(batch(eventId: '12345', entityType: 'none').hasEntity, isFalse);
    });

    test('is false when there is no id despite a type', () {
      expect(batch(eventId: '', entityType: 'event').hasEntity, isFalse);
    });
  });

  test('galleryId starts unset and is assigned once', () {
    // The first register chunk creates the gallery and returns its id; every
    // later chunk must reuse it or the photos split across two galleries.
    final b = batch(eventId: '', entityType: 'none');
    expect(b.galleryId, isNull);

    b.galleryId = 42;
    expect(b.galleryId, 42);
  });

  group('batchIdFor', () {
    test('names a standalone batch, which has no event id', () {
      expect(GalleryUploadProvider.batchIdFor(''), startsWith('gallery_'));
    });

    test('names a tagged batch after its entity', () {
      expect(GalleryUploadProvider.batchIdFor('4821'), startsWith('4821_'));
    });

    test('never collides, even called in a tight loop', () {
      // A timestamp alone collides within the same microsecond, and two
      // batches sharing an id would silently merge in the provider's map.
      final ids = {
        for (var i = 0; i < 500; i++) GalleryUploadProvider.batchIdFor(''),
      };
      expect(ids, hasLength(500));
    });
  });
}
