import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final VoidCallback? onTap;

  const ProfileAvatar({super.key, this.imageUrl, this.radius = 20, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundImage: hasImage
          ? NetworkImage(imageUrl!)
          : const AssetImage('assets/profile-placeholder.jpg') as ImageProvider,
      // Always safe to pass here: backgroundImage is never null — a
      // missing photo already falls back to the bundled placeholder,
      // so the assert that pairs these two cannot fire.
      onBackgroundImageError: (_, _) {},
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }

    return avatar;
  }
}
