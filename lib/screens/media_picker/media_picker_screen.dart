import 'dart:io';
import 'dart:ui' as ui;

import 'package:drivelife/services/media_location.dart';
import 'package:drivelife/utils/image_crop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
// Split out of photo_manager at 3.0. It is what caches decoded
// thumbnails between frames — without it the grid re-decodes every
// tile on each scroll and stutters badly on a large library.
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

const Color _gold = Color(0xFFAE9159);
const Color _ink = Color(0xFF1A1A1A);

/// The letterbox behind a photo that does not fill the pane.
///
/// Light grey rather than white, so the edges of a photo are visible
/// against it. On white, a white-background product shot appears to
/// bleed into the page and its framing cannot be judged — which is the
/// one thing this pane exists for.
const Color _mat = Color(0xFFEDEDED);

/// How an image was framed, kept so a reopened picker can restore it.
///
/// Opaque to callers: they hold it and hand it back, nothing more.
class MediaFraming {
  final double scale;
  final double dx;
  final double dy;
  final double viewportWidth;
  final double viewportHeight;

  const MediaFraming({
    required this.scale,
    required this.dx,
    required this.dy,
    required this.viewportWidth,
    required this.viewportHeight,
  });
}

/// One chosen item, and how its owner framed it.
class PickedMedia {
  /// The gallery's own id for this item.
  ///
  /// Carried so reopening the picker can preselect exactly what is
  /// already on the post, in the same order, with the same crops —
  /// rather than presenting an empty grid that has silently forgotten
  /// everything but the count.
  final String? assetId;

  /// Null when untouched.
  final MediaFraming? framing;

  /// The file to upload. Already cropped if they zoomed an image;
  /// otherwise the ORIGINAL file, untouched.
  final File file;

  /// Whether [file] is a re-render rather than the original.
  final bool cropped;

  final bool isVideo;

  /// Clip length, 0 for stills. Carried so the caller can apply its own
  /// limit without re-reading the file.
  final int durationSeconds;

  /// Where this was taken, and the story behind it.
  ///
  /// ── WHY IT IS READ HERE AND NOT LATER ───────────────────────────
  ///
  /// This is the LAST point at which it can be read. [file] may already
  /// be a crop, which is a freshly rendered bitmap carrying no EXIF at
  /// all, and the compressor and Cloudflare both strip metadata further
  /// down. The asset is the only thing that still knows, and it is only
  /// in scope right here.
  ///
  /// Carries the MISS as well as the hit, because most photos have no
  /// location and the reason matters — see [MediaLocationMiss].
  final MediaLocationReading? locationReading;

  /// Where this was taken, if anywhere. Null for most items, which is
  /// normal rather than a failure.
  MediaLocation? get location => locationReading?.location;

  /// When the camera says this was taken.
  ///
  /// From the asset's own creation date rather than the file's mtime:
  /// copying, compressing or cropping all rewrite the file's timestamp
  /// to now, which would date every photo to the moment it was posted.
  ///
  /// Needed because "what event was on here" is a question about a day
  /// as much as a place -- the same circuit is a different answer in
  /// July and in February.
  final DateTime? takenAt;

  const PickedMedia({
    required this.file,
    required this.cropped,
    this.isVideo = false,
    this.durationSeconds = 0,
    this.assetId,
    this.framing,
    this.locationReading,
    this.takenAt,
  });
}

/// The app's one media picker.
///
/// ── WHY THIS EXISTS INSTEAD OF image_picker ────────────────────────
///
/// Posts and garages kept acquiring photos nobody meant to add. The
/// system picker is a black box: it returns a list of files with no
/// confirmation step, so a stray tap on a crowded grid is indis-
/// tinguishable from a deliberate choice, and the first time anybody
/// sees what they picked is after it has been posted.
///
/// This puts a large preview above the grid. Every selection is shown
/// at size, swipeable, in order, and removable before going anywhere.
///
/// ── THE EDIT IS DELIBERATELY SMALL ─────────────────────────────────
///
/// Pinch to zoom, drag to move. No filters, rotation or aspect presets.
/// The viewport takes the image's OWN shape, so output aspect always
/// matches input — zooming crops in, it never reshapes, and nothing is
/// hidden from somebody who has not touched it.
///
/// Untouched photos pass through as their own file: no decode, no
/// re-encode, no generation lost, EXIF intact.
class MediaPickerScreen extends StatefulWidget {
  /// The TOTAL cap, including [alreadySelected].
  ///
  /// Expressed as a total rather than "how many more" so the counter
  /// can read 7/10 instead of 4/4, which is what made the old limit
  /// message say "up to 9" on a ten-item post.
  final int maxSelection;

  /// How many the caller is already holding.
  final int alreadySelected;

  final String confirmLabel;
  final String title;

  /// Offer videos alongside photos.
  final bool allowVideo;

  /// Longest clip offered, or null for no limit. Longer ones are shown
  /// but cannot be chosen, with the reason given.
  final Duration? maxVideoDuration;

  /// What is already on the post, to be preselected.
  ///
  /// Order and framing are restored from it, so reopening the picker
  /// shows the post as it stands rather than a blank grid. Items whose
  /// asset has since been deleted from the device are skipped.
  final List<PickedMedia> initialSelection;

  const MediaPickerScreen({
    super.key,
    this.maxSelection = 10,
    this.alreadySelected = 0,
    this.confirmLabel = 'Next',
    this.title = 'New post',
    this.allowVideo = true,
    this.maxVideoDuration,
    this.initialSelection = const [],
  });

  static Future<List<PickedMedia>?> open(
    BuildContext context, {
    int maxSelection = 10,
    int alreadySelected = 0,
    String confirmLabel = 'Next',
    String title = 'New post',
    bool allowVideo = true,
    Duration? maxVideoDuration,
    List<PickedMedia> initialSelection = const [],
  }) {
    return Navigator.of(context).push<List<PickedMedia>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MediaPickerScreen(
          maxSelection: maxSelection,
          alreadySelected: alreadySelected,
          confirmLabel: confirmLabel,
          title: title,
          allowVideo: allowVideo,
          maxVideoDuration: maxVideoDuration,
          initialSelection: initialSelection,
        ),
      ),
    );
  }

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  List<AssetPathEntity> _albums = const [];
  AssetPathEntity? _album;
  final List<AssetEntity> _assets = [];

  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  bool _denied = false;
  bool _limited = false;
  int _page = 0;
  static const int _pageSize = 90;

  /// A list, not a set: the ORDER is the order of the post, and it is
  /// shown as a number on each tile so it is never a guess.
  final List<AssetEntity> _selected = [];

  final Map<String, _Framing> _framing = {};

  /// Looking at something without choosing it. Cleared by any
  /// selection.
  AssetEntity? _peek;

  final _scroll = ScrollController();
  final _transform = TransformationController();
  late final PageController _pages;

  /// Page scrolling is blocked while zoomed, or the two gestures fight.
  bool _zoomed = false;

  bool _busy = false;

  int get _total => widget.alreadySelected + _selected.length;
  bool get _atLimit => _total >= widget.maxSelection;

  /// What the preview pane is paging over.
  List<AssetEntity> get _previewItems {
    if (_peek != null) return [_peek!];
    if (_selected.isNotEmpty) return _selected;
    return _assets.isEmpty ? const [] : [_assets.first];
  }

  @override
  void initState() {
    super.initState();
    _pages = PageController();
    _scroll.addListener(_onScroll);
    _transform.addListener(_onTransform);
    _start();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _transform.dispose();
    _pages.dispose();
    super.dispose();
  }

  // ── Loading ────────────────────────────────────────────────────────

  Future<void> _start() async {
    final permission = await PhotoManager.requestPermissionExtend();

    if (!mounted) return;

    if (!permission.hasAccess) {
      setState(() {
        _loading = false;
        _denied = true;
      });
      return;
    }

    _limited = permission == PermissionState.limited;

    final albums = await PhotoManager.getAssetPathList(
      type: widget.allowVideo ? RequestType.common : RequestType.image,
      onlyAll: false,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(needTitle: false),
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );

    if (!mounted) return;

    if (albums.isEmpty) {
      setState(() {
        _loading = false;
        _albums = const [];
      });
      return;
    }

    setState(() {
      _albums = albums;
      _album = albums.first;
    });

    await _restoreSelection();
    await _loadPage(reset: true);
  }

  /// Puts back what the post already holds.
  ///
  /// Looked up by id rather than matched on file paths, which change
  /// between picks. Anything since deleted from the device is skipped
  /// silently — it is already gone, and saying so here would be noise
  /// at the worst moment.
  Future<void> _restoreSelection() async {
    if (widget.initialSelection.isEmpty) return;

    final restored = <AssetEntity>[];

    for (final item in widget.initialSelection) {
      final id = item.assetId;
      if (id == null) continue;

      final asset = await AssetEntity.fromId(id);
      if (asset == null) continue;

      restored.add(asset);

      final framing = item.framing;
      if (framing != null) {
        _framing[id] = _Framing(
          framing.scale,
          Offset(framing.dx, framing.dy),
          ui.Size(framing.viewportWidth, framing.viewportHeight),
        );
      }
    }

    if (!mounted || restored.isEmpty) return;

    setState(() {
      _selected
        ..clear()
        ..addAll(restored);
    });
  }

  Future<void> _loadPage({bool reset = false}) async {
    final album = _album;
    if (album == null) return;

    if (reset) {
      _page = 0;
      _exhausted = false;
      _assets.clear();
    }

    final batch = await album.getAssetListPaged(page: _page, size: _pageSize);

    if (!mounted) return;

    setState(() {
      _assets.addAll(batch);
      _loading = false;
      _loadingMore = false;
      // Short batch means the album is done, which is what stops the
      // footer spinner sitting there for ever at the bottom.
      _exhausted = batch.length < _pageSize;
      _page++;
    });
  }

  void _onScroll() {
    if (_loadingMore || _loading || _exhausted) return;

    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 700) {
      setState(() => _loadingMore = true);
      _loadPage();
    }
  }

  // ── Framing ────────────────────────────────────────────────────────

  void _onTransform() {
    final items = _previewItems;
    if (items.isEmpty) return;

    final index = _pages.hasClients ? (_pages.page?.round() ?? 0) : 0;
    if (index < 0 || index >= items.length) return;

    final asset = items[index];
    if (asset.type != AssetType.image) return;

    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();

    final zoomed = scale > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);

    if (_selected.any((a) => a.id == asset.id)) {
      final existing = _framing[asset.id];
      _framing[asset.id] = _Framing(
        scale,
        Offset(matrix.getTranslation().x, matrix.getTranslation().y),
        existing?.viewport,
      );
    }
  }

  /// Moves the preview to [asset], resetting the zoom for the new one.
  ///
  /// The reset matters: carrying a zoom across to a photo of a
  /// different shape is what made a portrait appear stretched when it
  /// followed a landscape.
  void _previewAsset(AssetEntity asset) {
    final items = _previewItems;
    final index = items.indexWhere((a) => a.id == asset.id);

    _restoreFraming(asset);

    if (index >= 0 && _pages.hasClients) {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _restoreFraming(AssetEntity asset) {
    final saved = _framing[asset.id];

    _transform.value = saved == null
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(saved.translation.dx, saved.translation.dy, 0, 1)
            ..scaleByDouble(saved.scale, saved.scale, 1, 1));

    final zoomed = (saved?.scale ?? 1) > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  // ── Selection ──────────────────────────────────────────────────────

  bool _videoTooLong(AssetEntity asset) {
    final limit = widget.maxVideoDuration;
    return limit != null &&
        asset.type == AssetType.video &&
        asset.duration > limit.inSeconds;
  }

  void _toggle(AssetEntity asset) {
    final index = _selected.indexWhere((a) => a.id == asset.id);

    if (index >= 0) {
      HapticFeedback.mediumImpact();
      setState(() {
        _selected.removeAt(index);
        _framing.remove(asset.id);
        _peek = null;
      });
      return;
    }

    if (_videoTooLong(asset)) {
      HapticFeedback.heavyImpact();
      _say(
        'That clip is longer than '
        '${widget.maxVideoDuration!.inMinutes} minutes.',
      );
      return;
    }

    if (_atLimit) {
      HapticFeedback.heavyImpact();
      _say('You can add up to ${widget.maxSelection} in total.');
      return;
    }

    HapticFeedback.selectionClick();

    setState(() {
      _selected.add(asset);
      _peek = null;
    });

    // After the frame, so the PageView has the new page to move to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _previewAsset(asset);
    });
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _ink,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ── Confirm ────────────────────────────────────────────────────────

  /// The file behind an asset, fetching it from iCloud if it is not on
  /// the device.
  ///
  /// ── THIS IS THE iOS CASE THAT BITES ────────────────────────────────
  ///
  /// With "Optimise iPhone Storage" on — the default once a library
  /// outgrows the phone — the full photo lives in iCloud and only a
  /// thumbnail is local. `originFile` then returns null, and a picker
  /// that trusts it silently drops the photo somebody just chose.
  ///
  /// loadFile(isOrigin: true) downloads it instead. It can take a
  /// moment on a slow connection, which is why Next shows a spinner.
  Future<File?> _fileFor(AssetEntity asset) async {
    try {
      final origin = await asset.loadFile(isOrigin: true);
      if (origin != null) return origin;
    } catch (e) {
      debugPrint('[MediaPicker] origin load failed for ${asset.id}: $e');
    }

    try {
      // The prepared copy: already rotated and transcoded, and good
      // enough to post. Better than losing the item.
      return await asset.file;
    } catch (e) {
      debugPrint('[MediaPicker] file load failed for ${asset.id}: $e');
      return null;
    }
  }


  Future<void> _confirm() async {
    if (_selected.isEmpty || _busy) return;

    HapticFeedback.lightImpact();
    setState(() => _busy = true);

    final out = <PickedMedia>[];
    var failed = 0;

    // Asked once for the batch rather than once per photo. Not a gate:
    // a refusal is reported per item instead, so it cannot be mistaken
    // for a library of untagged photos.
    await MediaLocationService.ensureAccess();

    for (final asset in _selected) {
      final file = await _fileFor(asset);

      if (file == null) {
        failed++;
        continue;
      }

      // Read while the asset is still in hand, and BEFORE the crop
      // below: a crop is a freshly rendered bitmap with no EXIF, so
      // probing it would report a camera photo as a screenshot. The
      // compressor and the CDN strip what survives, so there is no
      // reading it back later either.
      final location = await MediaLocationService.read(asset, file: file);

      if (asset.type == AssetType.video) {
        out.add(
          PickedMedia(
            file: file,
            cropped: false,
            isVideo: true,
            durationSeconds: asset.duration,
            assetId: asset.id,
            locationReading: location,
            takenAt: asset.createDateTime,
          ),
        );
        continue;
      }

      final framing = _framing[asset.id];

      if (framing == null || isUncropped(framing.scale, framing.translation)) {
        out.add(
          PickedMedia(
            file: file,
            cropped: false,
            assetId: asset.id,
            locationReading: location,
            takenAt: asset.createDateTime,
          ),
        );
        continue;
      }

      final source = asset.orientatedSize;

      final cropped = await cropImageFile(
        file: file,
        srcRect: visibleSourceRect(
          source: source,
          viewport: framing.viewport ?? source,
          scale: framing.scale,
          translation: framing.translation,
        ),
        // The gallery and the decoder do not always agree about which
        // way up a photo is. Handing over what the rect was measured
        // against lets the crop land correctly either way.
        assumedSource: source,
      );

      // A failed crop keeps the original rather than dropping the
      // photo. Losing framing is a nuisance; losing the photo is not.
      out.add(
        PickedMedia(
          file: cropped ?? file,
          cropped: cropped != null,
          assetId: asset.id,
          // Survives the crop precisely BECAUSE it was read off the
          // asset: the cropped file itself carries no EXIF.
          locationReading: location,
          takenAt: asset.createDateTime,
          // Handed back so reopening the picker can restore this
          // exact framing rather than resetting it to untouched.
          framing: MediaFraming(
            scale: framing.scale,
            dx: framing.translation.dx,
            dy: framing.translation.dy,
            viewportWidth: (framing.viewport ?? source).width,
            viewportHeight: (framing.viewport ?? source).height,
          ),
        ),
      );
    }

    if (failed > 0 && mounted) {
      _say(
        failed == 1
            ? 'One item could not be opened and was skipped.'
            : '$failed items could not be opened and were skipped.',
      );
    }

    if (!mounted) return;

    setState(() => _busy = false);
    Navigator.of(context).pop(out);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        foregroundColor: _ink,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _albumButton(),
        centerTitle: true,
        actions: [_confirmButton()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFEAEAEA)),
        ),
      ),
      body: _body(),
    );
  }

  Widget _confirmButton() {
    final enabled = _selected.isNotEmpty && !_busy;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton(
        onPressed: enabled ? _confirm : null,
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
              )
            : AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  color: enabled ? _gold : Colors.grey.shade400,
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                ),
                child: Text(widget.confirmLabel),
              ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }

    if (_denied) return _permissionWall();

    if (_assets.isEmpty) {
      return Center(
        child: Text(
          widget.allowVideo ? 'No photos or videos found.' : 'No photos found.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return Column(
      children: [
        _preview(),
        if (_limited) _limitedBanner(),
        _selectionStrip(),
        Expanded(child: _grid()),
      ],
    );
  }

  /// The large pane: what you are about to post, at a size where a
  /// wrong photo is obvious. Swipe between your selections.
  Widget _preview() {
    final items = _previewItems;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = ui.Size(
          constraints.maxWidth,
          MediaQuery.sizeOf(context).height * 0.34,
        );

        if (items.isEmpty) {
          return SizedBox(width: available.width, height: available.height);
        }

        return SizedBox(
          width: available.width,
          height: available.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: _mat,
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: items.length,
                    physics: (_zoomed || items.length < 2)
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      _restoreFraming(items[i]);
                      setState(() {});
                    },
                    itemBuilder: (context, i) =>
                        _previewPage(items[i], available),
                  ),
                ),
              ),

              if (_peek != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _peekBar(),
                ),

              if (_peek == null && items.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: _dots(items.length),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _previewPage(AssetEntity asset, ui.Size available) {
    if (asset.type == AssetType.video) {
      return _VideoPreview(
        key: ValueKey('video-${asset.id}'),
        asset: asset,
        duration: _duration(asset.duration),
      );
    }

    // orientatedSize, NOT width/height.
    //
    // A JPEG carrying an EXIF rotation reports its raw dimensions while
    // decoding to the rotated ones, so a portrait photo can be reported
    // as landscape. Building the viewport from that gives a box of the
    // wrong shape, and BoxFit.fill then stretches the photo into it —
    // which is the warp that showed up when a portrait followed a
    // landscape.
    final source = asset.orientatedSize;
    final viewport = cropViewportFor(source, available);

    // The crop maths converts viewport units into source pixels, so the
    // viewport a framing was made against has to travel with it. It is
    // only known here, at layout time.
    final existing = _framing[asset.id];
    if (existing != null && existing.viewport != viewport) {
      _framing[asset.id] = existing.withViewport(viewport);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _blurredBackdrop(asset),
        Center(
          child: Container(
            width: viewport.width,
            height: viewport.height,
            // Lifts the sharp copy off the blurred one. Without it the
            // two blend at the seam and the photo's own edge — the
            // thing being judged — disappears.
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 18,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: ClipRect(
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: kMaxCropZoom,
                constrained: true,
                clipBehavior: Clip.hardEdge,
                onInteractionEnd: (_) {
                  final current = _framing[asset.id];
                  if (current != null) {
                    _framing[asset.id] = current.withViewport(viewport);
                  }
                },
                child: Image(
                  key: ValueKey(asset.id),
                  image: AssetEntityImageProvider(asset, isOriginal: true),
                  // Safe only because the viewport is built to the
                  // image's own aspect, so fill and contain agree. With
                  // gapless playback on, though, the PREVIOUS image
                  // would be drawn into this box and genuinely stretch
                  // — hence the key and gaplessPlayback: false.
                  fit: BoxFit.fill,
                  gaplessPlayback: false,
                  width: viewport.width,
                  height: viewport.height,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The letterbox, filled with a blurred copy of the photo itself.
  ///
  /// ── WHY THE THUMBNAIL AND NOT THE ORIGINAL ─────────────────────────
  ///
  /// A 28px blur over a 48-megapixel image is an expensive way to
  /// produce something indistinguishable from a 28px blur over a 200px
  /// thumbnail. The thumbnail is already decoded and cached for the
  /// grid, so this costs effectively nothing and does not stutter while
  /// swiping.
  ///
  /// Scaled past the edges on purpose: a blur samples beyond its own
  /// bounds and leaves a soft transparent rim otherwise, which reads as
  /// a rendering fault rather than a background.
  Widget _blurredBackdrop(AssetEntity asset) {
    return Positioned.fill(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Transform.scale(
                scale: 1.25,
                child: Image(
                  image: AssetEntityImageProvider(
                    asset,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(200),
                  ),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),

            // A wash over it, for the reason the mat was grey in the
            // first place: the pane exists to let somebody judge their
            // framing, and a photo sitting on a blurred copy of itself
            // has almost no edge at all. Knocking the backdrop back,
            // plus the shadow on the sharp copy, puts that edge back.
            Container(color: Colors.white.withValues(alpha: 0.28)),
          ],
        ),
      ),
    );
  }

  Widget _dots(int count) {
    final index = _pages.hasClients ? (_pages.page?.round() ?? 0) : 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count && count <= 12; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 7 : 5,
            height: i == index ? 7 : 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == index ? _gold : Colors.black26,
            ),
          ),
      ],
    );
  }

  Widget _peekBar() {
    final asset = _peek!;
    final tooLong = _videoTooLong(asset);

    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Just looking — not added yet',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: tooLong ? null : () => _toggle(asset),
            style: TextButton.styleFrom(
              foregroundColor: _gold,
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(tooLong ? 'Too long' : 'Add'),
          ),
          TextButton(
            onPressed: () => setState(() => _peek = null),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _limitedBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4E5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.brown.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You have shared only some photos with DriveLife.',
              style: TextStyle(color: Colors.brown.shade800, fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: PhotoManager.presentLimited,
            style: TextButton.styleFrom(
              foregroundColor: _gold,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Manage'),
          ),
        ],
      ),
    );
  }

  /// The chosen items, in order, always visible.
  ///
  /// Instagram hides this; here it stays, because a stray selection the
  /// user never scrolls back to is exactly the failure this screen was
  /// built to stop.
  Widget _selectionStrip() {
    final empty = _selected.isEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      height: empty ? 44 : 84,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEAEAEA))),
      ),
      child: empty
          ? Center(
              child: Text(
                widget.allowVideo
                    ? 'Tap to add photos or videos'
                    : 'Tap photos to add them',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
                  child: Row(
                    children: [
                      Text(
                        '$_total of ${widget.maxSelection} selected',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Drag to re-order',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _strip()),
              ],
            ),
    );
  }

  Widget _strip() {
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: _selected.length,
      onReorder: (from, to) {
        HapticFeedback.mediumImpact();
        setState(() {
          if (to > from) to -= 1;
          _selected.insert(to, _selected.removeAt(from));
        });
      },
      proxyDecorator: (child, index, animation) =>
          Material(color: Colors.transparent, child: child),
      itemBuilder: (context, i) {
        final asset = _selected[i];
        final pageIndex = _pages.hasClients ? (_pages.page?.round() ?? 0) : 0;
        final active = _peek == null && pageIndex == i;

        return ReorderableDelayedDragStartListener(
          key: ValueKey(asset.id),
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _StripTile(
              asset: asset,
              active: active,
              onTap: () {
                setState(() => _peek = null);
                _previewAsset(asset);
              },
              onRemove: () => _toggle(asset),
            ),
          ),
        );
      },
    );
  }

  Widget _grid() {
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(1),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _tile(_assets[i]),
              childCount: _assets.length,
            ),
          ),
        ),

        // The loader item 5 asked for. Only while more is actually
        // coming — _exhausted stops it sitting at the bottom for ever
        // once the album has run out.
        SliverToBoxAdapter(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              height: _loadingMore ? 64 : 0,
              child: _loadingMore
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _gold,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(AssetEntity asset) {
    final order = _selected.indexWhere((a) => a.id == asset.id);
    final isSelected = order >= 0;
    final isVideo = asset.type == AssetType.video;
    final tooLong = _videoTooLong(asset);
    final blocked = !isSelected && (_atLimit || tooLong);

    return GestureDetector(
      // Tap selects. Long-press previews WITHOUT selecting, so a closer
      // look never costs an unwanted photo — the exact mistake this
      // screen exists to prevent.
      onTap: () => _toggle(asset),
      onLongPress: () {
        HapticFeedback.lightImpact();
        setState(() => _peek = asset);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: AssetEntityImageProvider(
              asset,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(300),
            ),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),

          // Greyed when it cannot be chosen, so the limit is visible
          // before the tap rather than explained after it.
          if (blocked)
            Container(color: Colors.white.withValues(alpha: 0.6)),

          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? _gold : Colors.transparent,
                width: isSelected ? 3 : 0,
              ),
            ),
          ),

          if (isVideo)
            Positioned(
              left: 4,
              bottom: 4,
              child: _pill(_duration(asset.duration), small: true),
            ),

          Positioned(
            top: 5,
            right: 5,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              scale: isSelected ? 1 : 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: isSelected ? 1 : 0,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: _gold,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 3),
                    ],
                  ),
                  child: Text(
                    '${order + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, {bool small = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 5 : 8,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _duration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _albumButton() {
    if (_albums.isEmpty) {
      return Text(
        widget.title,
        style: const TextStyle(color: _ink, fontSize: 16),
      );
    }

    return InkWell(
      onTap: _pickAlbum,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _album?.name ?? widget.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: _ink, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAlbum() async {
    final chosen = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _albums.length,
          itemBuilder: (context, i) {
            final album = _albums[i];
            return ListTile(
              title: Text(album.name, style: const TextStyle(color: _ink)),
              trailing: album.id == _album?.id
                  ? const Icon(Icons.check, color: _gold, size: 18)
                  : null,
              onTap: () => Navigator.pop(context, album),
            );
          },
        ),
      ),
    );

    if (chosen == null || chosen.id == _album?.id || !mounted) return;

    setState(() {
      _album = chosen;
      _loading = true;
    });

    await _loadPage(reset: true);
  }

  Widget _permissionWall() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 42,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          const Text(
            'DriveLife needs access to your photos',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'So you can see and choose what you are posting before it '
            'goes anywhere.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: PhotoManager.openSetting,
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }
}

/// A clip in the preview pane, that actually plays.
///
/// ── WHY A WIDGET AND NOT A PLAY ICON ───────────────────────────────
///
/// The first version drew a play button over a still and did nothing
/// when tapped, which is worse than showing no button: it says the
/// control exists and then ignores you. Checking a clip before posting
/// it is the same need as checking a photo, so it has to really play.
///
/// One controller, created with this page and disposed with it.
/// PageView.builder only keeps neighbouring pages alive, so swiping
/// away from a clip tears its controller down — which is what stops a
/// long selection holding a dozen decoders open at once.
class _VideoPreview extends StatefulWidget {
  final AssetEntity asset;
  final String duration;

  const _VideoPreview({
    super.key,
    required this.asset,
    required this.duration,
  });

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // The prepared copy rather than the original: it is already
      // transcoded to something the platform player can open, which
      // the camera original is not always.
      final file = await widget.asset.file;

      if (file == null) {
        if (mounted) setState(() => _failed = true);
        return;
      }

      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);

      if (!mounted) {
        // Lost the race with a swipe away. Nothing will dispose this
        // but us.
        await controller.dispose();
        return;
      }

      setState(() => _controller = controller);
    } catch (e) {
      debugPrint('[MediaPicker] video init failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null) return;

    HapticFeedback.selectionClick();

    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined,
                size: 30, color: Colors.grey.shade500),
            const SizedBox(height: 8),
            Text(
              'This clip could not be previewed.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (controller == null) {
      // The thumbnail while the decoder warms up, so the pane never
      // flashes empty when swiping onto a clip.
      return Stack(
        alignment: Alignment.center,
        children: [
          Image(
            image: AssetEntityImageProvider(
              widget.asset,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(1000),
            ),
            fit: BoxFit.contain,
          ),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ],
      );
    }

    final playing = controller.value.isPlaying;

    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The same blurred fill the photos get. A clip on flat grey
          // beside a photo on a blurred backdrop looks like one of the
          // two is broken.
          Positioned.fill(
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Transform.scale(
                      scale: 1.25,
                      child: Image(
                        image: AssetEntityImageProvider(
                          widget.asset,
                          isOriginal: false,
                          thumbnailSize: const ThumbnailSize.square(200),
                        ),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  Container(color: Colors.white.withValues(alpha: 0.28)),
                ],
              ),
            ),
          ),

          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),

          // Fades out while playing rather than vanishing, so the tap
          // target is still obviously there.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: playing ? 0 : 1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(14),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: _gold,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
            ),
          ),

          Positioned(
            bottom: 10,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.duration,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One thumbnail in the selection strip, with its own entrance.
///
/// A separate widget so the scale-in runs when it is first inserted
/// rather than on every parent rebuild.
class _StripTile extends StatefulWidget {
  final AssetEntity asset;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _StripTile({
    required this.asset,
    required this.active,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_StripTile> createState() => _StripTileState();
}

class _StripTileState extends State<_StripTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _in, curve: Curves.easeOutBack),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.active ? _gold : const Color(0xFFE2E2E2),
                  width: widget.active ? 2.5 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image(
                image: AssetEntityImageProvider(
                  widget.asset,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(200),
                ),
                fit: BoxFit.cover,
              ),
            ),
            if (widget.asset.type == AssetType.video)
              const Positioned(
                left: 4,
                bottom: 4,
                child: Icon(
                  Icons.videocam_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            Positioned(
              top: -5,
              right: -5,
              child: GestureDetector(
                onTap: widget.onRemove,
                child: Container(
                  decoration: BoxDecoration(
                    color: _ink,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(
                    Icons.close,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A remembered zoom, and the viewport it was made against.
///
/// The viewport matters: the crop maths converts viewport units into
/// source pixels, so a transform without the box it was made in cannot
/// be turned back into a rectangle of the photo.
class _Framing {
  final double scale;
  final Offset translation;
  final ui.Size? viewport;

  const _Framing(this.scale, this.translation, [this.viewport]);

  _Framing withViewport(ui.Size size) => _Framing(scale, translation, size);
}
