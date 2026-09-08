import 'package:drivelife/utils/gallery_photo_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('galleryPickBudget', () {
    test('a fresh screen may pick the whole limit', () {
      expect(galleryPickBudget(0), kGalleryPickLimit);
    });

    test('tops up rather than restarting the count', () {
      expect(galleryPickBudget(30), kGalleryPickLimit - 30);
    });

    test('is zero at the limit', () {
      expect(galleryPickBudget(kGalleryPickLimit), 0);
    });

    test('never goes negative', () {
      // A negative budget would read as "no cap" everywhere downstream.
      expect(galleryPickBudget(kGalleryPickLimit + 20), 0);
    });
  });

  group('galleryPickerLimit', () {
    test('passes the budget through when the platform accepts it', () {
      expect(galleryPickerLimit(50), 50);
      expect(galleryPickerLimit(2), 2);
    });

    test('goes uncapped for the last free slot', () {
      // The platform interface throws below 2, so one slot left MUST be null
      // and trimmed on the way back instead.
      expect(galleryPickerLimit(1), isNull);
    });

    test('goes uncapped rather than passing zero', () {
      expect(galleryPickerLimit(0), isNull);
    });
  });
}
