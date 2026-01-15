import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

enum ImagePickerMode { profile, cover, post }

class CustomImagePicker extends StatefulWidget {
  final ImagePickerMode mode;
  final int maxSelection;
  final Function(List<File>) onImagesSelected;

  const CustomImagePicker({
    super.key,
    required this.mode,
    this.maxSelection = 10,
    required this.onImagesSelected,
  });

  @override
  State<CustomImagePicker> createState() => _CustomImagePickerState();
}

class _CustomImagePickerState extends State<CustomImagePicker> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _mediaList = [];
  List<AssetEntity> _selectedAssets = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 0;
  static const int _pageSize = 60;
  bool _hasMoreToLoad = true;
  bool _isMultiSelectMode = false;

  final ScrollController _scrollController = ScrollController();
  final Map<String, Uint8List> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoadAlbums();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _thumbnailCache.clear();
    _mediaList.clear();
    _selectedAssets.clear();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_isLoadingMore &&
        _hasMoreToLoad) {
      _loadMoreAssets();
    }
  }

  Future<void> _requestPermissionAndLoadAlbums() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();

    if (ps.isAuth || ps == PermissionState.limited) {
      await _loadAlbums();
    } else {
      if (mounted) {
        _showPermissionDeniedDialog();
      }
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Please grant photo library access to select images.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              PhotoManager.openSetting();
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAlbums() async {
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: false,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );

    if (albums.isNotEmpty) {
      setState(() {
        _albums = albums;
        _selectedAlbum = albums[0];
      });
      await _loadAssets();
    }
  }

  Future<void> _loadAssets() async {
    if (_selectedAlbum == null) return;

    setState(() => _isLoading = true);

    final assets = await _selectedAlbum!.getAssetListPaged(
      page: _currentPage,
      size: _pageSize,
    );

    if (mounted) {
      setState(() {
        if (_currentPage == 0) {
          _mediaList = assets;
          if (assets.isNotEmpty) {
            _selectedAssets = [assets[0]];
          }
        } else {
          _mediaList.addAll(assets);
        }
        _hasMoreToLoad = assets.length == _pageSize;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreAssets() async {
    if (_selectedAlbum == null || _isLoadingMore || !_hasMoreToLoad) return;

    setState(() => _isLoadingMore = true);

    _currentPage++;
    final assets = await _selectedAlbum!.getAssetListPaged(
      page: _currentPage,
      size: _pageSize,
    );

    if (mounted) {
      setState(() {
        _mediaList.addAll(assets);
        _hasMoreToLoad = assets.length == _pageSize;
        _isLoadingMore = false;
      });
    }
  }

  void _onImageTap(AssetEntity asset) {
    if (_isMultiSelectMode) {
      setState(() {
        if (_selectedAssets.contains(asset)) {
          _selectedAssets.remove(asset);
        } else {
          if (_selectedAssets.length < widget.maxSelection) {
            _selectedAssets.add(asset);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Maximum ${widget.maxSelection} images allowed'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      });
    } else {
      _selectedAssets = [asset];
      setState(() {});
    }
  }

  void _toggleMultiSelect() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      if (!_isMultiSelectMode && _selectedAssets.length > 1) {
        // Keep only the first selected image
        _selectedAssets = [_selectedAssets.first];
      }
    });
  }

  Future<void> _onNext() async {
    if (_selectedAssets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one image')),
      );
      return;
    }

    List<File> files = [];
    for (var asset in _selectedAssets) {
      final file = await asset.file;
      if (file != null) {
        files.add(file);
      }
    }

    widget.onImagesSelected(files);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _showAlbumSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Select Album',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _albums.length,
                itemBuilder: (context, index) {
                  final album = _albums[index];
                  final isSelected = album.id == _selectedAlbum?.id;

                  return FutureBuilder<int>(
                    future: album.assetCountAsync,
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;

                      return ListTile(
                        leading: FutureBuilder<List<AssetEntity>>(
                          future: album.getAssetListRange(start: 0, end: 1),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: _buildThumbnail(
                                  snapshot.data![0],
                                  50,
                                  50,
                                ),
                              );
                            }
                            return Container(
                              width: 50,
                              height: 50,
                              color: Colors.grey.shade300,
                            );
                          },
                        ),
                        title: Text(
                          album.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text('$count items'),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFFAE9159))
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedAlbum = album;
                            _currentPage = 0;
                            _mediaList.clear();
                            _selectedAssets.clear();
                            _hasMoreToLoad = true;
                            _thumbnailCache.clear();
                          });
                          _loadAssets();
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(AssetEntity asset, int width, int height) {
    final cacheKey = '${asset.id}_${width}x$height';

    if (_thumbnailCache.containsKey(cacheKey)) {
      return Image.memory(
        _thumbnailCache[cacheKey]!,
        width: width.toDouble(),
        height: height.toDouble(),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(ThumbnailSize(width, height)),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          _thumbnailCache[cacheKey] = snapshot.data!;
          return Image.memory(
            snapshot.data!,
            width: width.toDouble(),
            height: height.toDouble(),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }
        return Container(
          width: width.toDouble(),
          height: height.toDouble(),
          color: Colors.grey.shade300,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'New post',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _onNext,
            child: const Text(
              'Next',
              style: TextStyle(
                color: Color(0xFF4A9EFF),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Preview Section - Always visible, 1:1 aspect ratio for post mode
                if (_selectedAssets.isNotEmpty)
                  RepaintBoundary(
                    child: AdjustableImagePreview(
                      key: ValueKey(_selectedAssets[0].id),
                      asset: _selectedAssets[0],
                      mode: widget.mode,
                      width: screenWidth,
                    ),
                  ),

                // Album selector and multi-select button
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // Album selector
                      Expanded(
                        child: GestureDetector(
                          onTap: _showAlbumSelector,
                          child: Row(
                            children: [
                              Text(
                                _selectedAlbum?.name ?? 'Recents',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.keyboard_arrow_down,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Multi-select toggle button (only for post mode)
                      if (widget.mode == ImagePickerMode.post)
                        GestureDetector(
                          onTap: _toggleMultiSelect,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              color: _isMultiSelectMode
                                  ? const Color(0xFF4A9EFF)
                                  : Colors.transparent,
                            ),
                            child: _isMultiSelectMode
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : Stack(
                                    children: [
                                      Positioned(
                                        right: 2,
                                        bottom: 2,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Grid Section
                Expanded(
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(1),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 1,
                          mainAxisSpacing: 1,
                        ),
                    itemCount: _mediaList.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _mediaList.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }

                      final asset = _mediaList[index];
                      final isSelected = _selectedAssets.contains(asset);
                      final selectionIndex = _selectedAssets.indexOf(asset);

                      return GestureDetector(
                        onTap: () => _onImageTap(asset),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            RepaintBoundary(
                              child: _buildThumbnail(asset, 200, 200),
                            ),

                            // Selection indicator
                            if (_isMultiSelectMode || isSelected)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected
                                        ? const Color(0xFF4A9EFF)
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected && _isMultiSelectMode
                                      ? Center(
                                          child: Text(
                                            '${selectionIndex + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// Separate StatefulWidget for preview
class AdjustableImagePreview extends StatefulWidget {
  final AssetEntity asset;
  final ImagePickerMode mode;
  final double width;

  const AdjustableImagePreview({
    super.key,
    required this.asset,
    required this.mode,
    required this.width,
  });

  @override
  State<AdjustableImagePreview> createState() => _AdjustableImagePreviewState();
}

class _AdjustableImagePreviewState extends State<AdjustableImagePreview> {
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  Uint8List? _imageData;
  bool _isLoading = true;
  Size? _imageSize;
  Size? _containerSize;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    ThumbnailSize size;

    if (widget.mode == ImagePickerMode.profile) {
      size = const ThumbnailSize(800, 800);
    } else if (widget.mode == ImagePickerMode.cover) {
      size = const ThumbnailSize(1200, 600);
    } else {
      // Post mode - load high quality square image
      size = const ThumbnailSize(1200, 1200);
    }

    final data = await widget.asset.thumbnailDataWithSize(size);
    if (mounted) {
      setState(() {
        _imageData = data;
        _isLoading = false;
      });
    }
  }

  Offset _clampOffset(Offset offset, Size imageSize, Size containerSize) {
    final scaledWidth = imageSize.width * _scale;
    final scaledHeight = imageSize.height * _scale;

    if (scaledWidth <= containerSize.width &&
        scaledHeight <= containerSize.height) {
      return Offset.zero;
    }

    double maxX = 0;
    double maxY = 0;

    if (scaledWidth > containerSize.width) {
      maxX = (scaledWidth - containerSize.width) / 2;
    }

    if (scaledHeight > containerSize.height) {
      maxY = (scaledHeight - containerSize.height) / 2;
    }

    return Offset(offset.dx.clamp(-maxX, maxX), offset.dy.clamp(-maxY, maxY));
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_imageSize != null && _containerSize != null) {
      final clampedOffset = _clampOffset(_offset, _imageSize!, _containerSize!);

      if (_offset != clampedOffset) {
        setState(() {
          _offset = clampedOffset;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == ImagePickerMode.post) {
      return _buildPostPreview();
    } else if (widget.mode == ImagePickerMode.profile) {
      return _buildProfilePreview();
    } else {
      return _buildCoverPreview();
    }
  }

  Widget _buildPostPreview() {
    // 1:1 square aspect ratio, full width
    _containerSize = Size(widget.width, widget.width);
    _imageSize = const Size(1200, 1200);

    return Container(
      width: widget.width,
      height: widget.width, // 1:1 aspect ratio
      color: Colors.black,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ClipRect(
              child: GestureDetector(
                onScaleStart: (details) {
                  // Store for later if needed
                },
                onScaleUpdate: (details) {
                  setState(() {
                    _scale = (_scale * details.scale).clamp(1.0, 3.0);

                    final newOffset = _offset + details.focalPointDelta;
                    _offset = _clampOffset(
                      newOffset,
                      _imageSize!,
                      _containerSize!,
                    );
                  });
                },
                onScaleEnd: _onScaleEnd,
                child: Transform.scale(
                  scale: _scale,
                  child: Transform.translate(
                    offset: _offset,
                    child: Image.memory(
                      _imageData!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      width: widget.width,
                      height: widget.width,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildProfilePreview() {
    _containerSize = const Size(250, 250);
    _imageSize = const Size(800, 800);

    return Container(
      width: double.infinity,
      height: 300,
      color: Colors.black,
      child: Center(
        child: ClipOval(
          child: Container(
            width: 250,
            height: 250,
            color: Colors.grey.shade900,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : GestureDetector(
                    onScaleStart: (details) {},
                    onScaleUpdate: (details) {
                      setState(() {
                        _scale = (_scale * details.scale).clamp(1.0, 3.0);

                        final newOffset = _offset + details.focalPointDelta;
                        _offset = _clampOffset(
                          newOffset,
                          _imageSize!,
                          _containerSize!,
                        );
                      });
                    },
                    onScaleEnd: _onScaleEnd,
                    child: Transform.scale(
                      scale: _scale,
                      child: Transform.translate(
                        offset: _offset,
                        child: Image.memory(
                          _imageData!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverPreview() {
    final screenWidth = MediaQuery.of(context).size.width - 32;
    _containerSize = Size(screenWidth, 200);
    _imageSize = const Size(1200, 600);

    return Container(
      width: double.infinity,
      height: 300,
      color: Colors.black,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            height: 200,
            color: Colors.grey.shade900,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : GestureDetector(
                    onScaleStart: (details) {},
                    onScaleUpdate: (details) {
                      setState(() {
                        _scale = (_scale * details.scale).clamp(1.0, 3.0);

                        final newOffset = _offset + details.focalPointDelta;
                        _offset = _clampOffset(
                          newOffset,
                          _imageSize!,
                          _containerSize!,
                        );
                      });
                    },
                    onScaleEnd: _onScaleEnd,
                    child: Transform.scale(
                      scale: _scale,
                      child: Transform.translate(
                        offset: _offset,
                        child: Image.memory(
                          _imageData!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
