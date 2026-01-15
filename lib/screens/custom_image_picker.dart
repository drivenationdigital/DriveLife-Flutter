import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

enum ImagePickerMode {
  profile, // Circular preview for profile pictures
  cover, // Rectangular preview for cover images
  post, // Multi-select for posts
}

class CustomImagePicker extends StatefulWidget {
  final ImagePickerMode mode;
  final int maxSelection; // For multi-select mode
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
  int _currentPage = 0;
  static const int _pageSize = 50;

  // Helper widget to display asset image
  Widget _buildAssetImage(
    AssetEntity asset, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(
        ThumbnailSize((width ?? 300).toInt(), (height ?? 300).toInt()),
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            width: width,
            height: height,
            fit: fit,
          );
        }
        return Container(
          width: width,
          height: height,
          color: Colors.grey.shade300,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoadAlbums();
  }

  Future<void> _requestPermissionAndLoadAlbums() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();

    print('PhotoManager PermissionState: $ps');

    if (ps.isAuth) {
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
    );

    if (albums.isNotEmpty) {
      setState(() {
        _albums = albums;
        _selectedAlbum = albums[0]; // Default to "Recents"
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

    setState(() {
      if (_currentPage == 0) {
        _mediaList = assets;
        // Auto-select first image for single select modes
        if (widget.mode != ImagePickerMode.post && assets.isNotEmpty) {
          _selectedAssets = [assets[0]];
        }
      } else {
        _mediaList.addAll(assets);
      }
      _isLoading = false;
    });
  }

  void _onImageTap(AssetEntity asset) {
    setState(() {
      if (widget.mode == ImagePickerMode.post) {
        // Multi-select mode
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
      } else {
        // Single select mode
        _selectedAssets = [asset];
      }
    });
  }

  Future<void> _onDone() async {
    if (_selectedAssets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one image')),
      );
      return;
    }

    // Convert AssetEntity to File
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
                                child: _buildAssetImage(
                                  snapshot.data![0],
                                  width: 50,
                                  height: 50,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: _showAlbumSelector,
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
              const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _onDone,
            child: const Text(
              'Done',
              style: TextStyle(
                color: Color(0xFFAE9159),
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
                // Preview Section
                if (_selectedAssets.isNotEmpty)
                  _buildPreview(_selectedAssets[0]),

                // Grid Section
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(2),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                        ),
                    itemCount: _mediaList.length,
                    itemBuilder: (context, index) {
                      final asset = _mediaList[index];
                      final isSelected = _selectedAssets.contains(asset);
                      final selectionIndex = _selectedAssets.indexOf(asset);

                      return GestureDetector(
                        onTap: () => _onImageTap(asset),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildAssetImage(asset),
                            if (isSelected)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFAE9159),
                                    width: 3,
                                  ),
                                ),
                              ),
                            if (widget.mode == ImagePickerMode.post &&
                                isSelected)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFAE9159),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${selectionIndex + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
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

  Widget _buildPreview(AssetEntity asset) {
    return Container(
      width: double.infinity,
      height: 300,
      color: Colors.black,
      child: Center(
        child: widget.mode == ImagePickerMode.profile
            ? ClipOval(
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: _buildAssetImage(asset, width: 200, height: 200),
                ),
              )
            : widget.mode == ImagePickerMode.cover
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: double.infinity,
                  height: 200,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildAssetImage(asset, width: 800, height: 400),
                  ),
                ),
              )
            : _buildAssetImage(
                asset,
                width: 800,
                height: 800,
                fit: BoxFit.contain,
              ),
      ),
    );
  }
}
