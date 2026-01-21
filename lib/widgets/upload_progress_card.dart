import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drivelife/providers/upload_post_provider.dart';

class UploadProgressCard extends StatelessWidget {
  final String uploadId;
  final UploadPostProgress progress;

  const UploadProgressCard({
    Key? key,
    required this.uploadId,
    required this.progress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatusIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getTitle(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progress.statusMessage,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (progress.status == UploadStatus.uploading ||
                  progress.status == UploadStatus.processing)
                _buildProgressIndicator()
              else if (progress.status == UploadStatus.completed)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.green,
                    size: 24,
                  ),
                )
              else if (progress.status == UploadStatus.failed)
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.red),
                  onPressed: () {
                    context.read<UploadPostProvider>().cancelUpload(uploadId);
                  },
                ),
            ],
          ),

          if (progress.status == UploadStatus.uploading ||
              progress.status == UploadStatus.processing) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFAE9159),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress.progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (progress.totalItems > 0)
                  Text(
                    '${progress.currentItem}/${progress.totalItems} items',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ],

          if (progress.status == UploadStatus.failed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      progress.error ?? 'Upload failed',
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                // Implement retry logic
                context.read<UploadPostProvider>().retryUpload(uploadId);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFAE9159),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;

    switch (progress.status) {
      case UploadStatus.uploading:
      case UploadStatus.processing:
        icon = Icons.cloud_upload_rounded;
        color = const Color(0xFFAE9159);
        break;
      case UploadStatus.completed:
        icon = Icons.cloud_done_rounded;
        color = Colors.green;
        break;
      case UploadStatus.failed:
        icon = Icons.cloud_off_rounded;
        color = Colors.red;
        break;
      default:
        icon = Icons.cloud_queue_rounded;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildProgressIndicator() {
    return SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(
        value: progress.progress,
        strokeWidth: 3,
        backgroundColor: Colors.grey.shade200,
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFAE9159)),
      ),
    );
  }

  String _getTitle() {
    switch (progress.status) {
      case UploadStatus.uploading:
        return 'Uploading Post';
      case UploadStatus.processing:
        return 'Processing Post';
      case UploadStatus.completed:
        return 'Post Created!';
      case UploadStatus.failed:
        return 'Upload Failed';
      default:
        return 'Preparing...';
    }
  }
}
