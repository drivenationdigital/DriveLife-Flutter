import 'package:cached_network_image/cached_network_image.dart';
import 'package:drivelife/api/media_api.dart';
import 'package:drivelife/models/media_models.dart';
import 'package:drivelife/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Approval queue for photos the AI matched to the user's garage vehicles.
///
/// Decisions are optimistic — the card leaves the list immediately and is put
/// back if the request fails, so a slow connection never blocks the queue.
class ImagesOfYouScreen extends StatefulWidget {
  const ImagesOfYouScreen({super.key});

  @override
  State<ImagesOfYouScreen> createState() => _ImagesOfYouScreenState();
}

class _ImagesOfYouScreenState extends State<ImagesOfYouScreen> {
  List<PendingImage> _images = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);

    try {
      final result = await MediaAPI.getMatches(status: 'pending', limit: 50);
      print(result.data);
      if (!mounted) return;
      setState(() {
        _images = result.data;
        _error = null;
        _loading = false;
      });
    } on MediaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _resolve(PendingImage image, {required bool approved}) async {
    final index = _images.indexOf(image);
    if (index < 0) return;

    HapticFeedback.lightImpact();
    setState(() => _images.removeAt(index));

    try {
      await MediaAPI.decide(
        mediaId: image.id,
        decision: approved ? 'accepted' : 'declined',
      );
      _toast(
        approved
            ? 'Photo approved — you are now tagged in it.'
            : 'Photo declined. It will not appear on your profile.',
      );
    } on MediaApiException catch (e) {
      // Put it back where it was so the queue order survives a failure.
      if (!mounted) return;
      setState(() => _images.insert(index.clamp(0, _images.length), image));
      _toast(e.message);
    }
  }

  Future<void> _approveAll() async {
    final count = _images.length;
    if (count == 0 || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve all photos?'),
        content: Text(
          'All $count photos will appear on your profile and in the event '
          'galleries you are tagged in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve all'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final snapshot = List<PendingImage>.from(_images);

    try {
      final affected = await MediaAPI.decideAll(decision: 'accepted');
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _images = [];
        _busy = false;
      });
      _toast('Approved $affected photo${affected == 1 ? '' : 's'}.');
    } on MediaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _images = snapshot;
        _busy = false;
      });
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);
    final canApproveAll = _images.isNotEmpty && !_busy;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 32, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Images of you',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _loading ? 'Loading…' : '${_images.length} pending review',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: canApproveAll ? _approveAll : null,
            child: Text(
              'Approve all',
              style: TextStyle(
                color: canApproveAll
                    ? theme.primaryColor
                    : Colors.grey.shade400,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: RefreshIndicator(
        color: theme.primaryColor,
        onRefresh: _load,
        child: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeProvider theme) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: theme.primaryColor,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_error != null) {
      return _MessageState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load',
        body: _error!,
        action: TextButton(onPressed: _load, child: const Text('Try again')),
      );
    }

    if (_images.isEmpty) {
      return const _MessageState(
        icon: Icons.check_circle_outline,
        title: 'All caught up',
        body: 'Nothing left to review.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      // One extra leading item for the explanatory blurb above the cards.
      itemCount: _images.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Approved photos appear on your profile and in event galleries '
              'you are tagged in.',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
          );
        }

        final image = _images[index - 1];

        return _PendingImageCard(
          key: ValueKey(image.id),
          image: image,
          primaryColor: theme.primaryColor,
          onApprove: () => _resolve(image, approved: true),
          onReject: () => _resolve(image, approved: false),
        );
      },
    );
  }
}

/// Centred message that still scrolls, so pull-to-refresh keeps working on the
/// empty and error states.
class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 52, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13.5,
                      ),
                    ),
                    if (action != null) ...[const SizedBox(height: 8), action!],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PendingImageCard extends StatelessWidget {
  final PendingImage image;
  final Color primaryColor;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingImageCard({
    super.key,
    required this.image,
    required this.primaryColor,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: CachedNetworkImage(
              imageUrl: image.imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: Colors.grey.shade200),
              errorWidget: (_, __, ___) => Container(
                color: Colors.grey.shade200,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _Avatar(url: image.userAvatarUrl, username: image.username),
                const SizedBox(width: 12),
                Expanded(child: _buildMeta()),
                const SizedBox(width: 8),
                _CircleAction(
                  icon: Icons.close,
                  iconColor: Colors.grey.shade700,
                  backgroundColor: Colors.white,
                  borderColor: Colors.grey.shade300,
                  onTap: onReject,
                  semanticLabel: 'Reject photo',
                ),
                const SizedBox(width: 10),
                _CircleAction(
                  icon: Icons.check,
                  iconColor: primaryColor,
                  backgroundColor: Colors.black,
                  onTap: onApprove,
                  semanticLabel: 'Approve photo',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeta() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                '@${image.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (image.userVerified) ...[
              const SizedBox(width: 4),
              Icon(Icons.verified, size: 14, color: primaryColor),
            ],
          ],
        ),
        if (image.locationName != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 14,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  image.locationName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 2),
        Text(
          image.addedLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

/// Poster avatar, falling back to their initial when there's no image.
class _Avatar extends StatelessWidget {
  final String? url;
  final String username;

  const _Avatar({required this.url, required this.username});

  @override
  Widget build(BuildContext context) {
    final initial = username.isEmpty ? '?' : username[0].toUpperCase();

    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: url == null ? null : CachedNetworkImageProvider(url!),
      child: url == null
          ? Text(
              initial,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color? borderColor;
  final VoidCallback onTap;
  final String semanticLabel;

  const _CircleAction({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.onTap,
    required this.semanticLabel,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: backgroundColor,
        shape: CircleBorder(
          side: borderColor == null
              ? BorderSide.none
              : BorderSide(color: borderColor!),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 21, color: iconColor),
          ),
        ),
      ),
    );
  }
}
