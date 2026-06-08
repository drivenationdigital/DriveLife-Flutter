import 'package:flutter/material.dart';

const Color _gold = Color(0xFFC4A062);
const Color _ink = Color(0xFF0B0B0B);
const Color _muted = Color(0xFF8A8A8A);

enum MemberAdminAction { viewProfile, makeAdmin, removeAdmin, remove, block }

class MemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool isViewerAdmin;
  final VoidCallback onTap;
  final VoidCallback? onViewRequest;
  final void Function(MemberAdminAction) onAdminAction;

  const MemberRow({
    super.key,
    required this.member,
    required this.isViewerAdmin,
    required this.onTap,
    required this.onAdminAction,
    this.onViewRequest,
  });

  @override
  Widget build(BuildContext context) {
    final name = (member['name'] ?? '') as String;
    final avatar = member['avatar'] as String?;
    final isOwner = member['is_owner'] == true;
    final isAdmin = member['is_admin'] == true;
    final isPending = member['is_pending'] == true;

    return InkWell(
      onTap: isPending ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _gold.withOpacity(0.15),
              backgroundImage: (avatar != null && avatar.isNotEmpty)
                  ? NetworkImage(avatar)
                  : null,
              child: (avatar == null || avatar.isEmpty)
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isOwner || isAdmin || isPending) ...[
                    const SizedBox(height: 2),
                    _RoleBadge(
                      label: isOwner
                          ? 'Owner'
                          : isAdmin
                          ? 'Admin'
                          : 'Pending',
                      isPending: isPending,
                    ),
                  ],
                ],
              ),
            ),

            // Right-side action area
            if (isPending && isViewerAdmin && onViewRequest != null)
              OutlinedButton(
                onPressed: onViewRequest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gold,
                  side: const BorderSide(color: _gold, width: 1.2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text(
                  'View request',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              )
            else if ((isViewerAdmin || isOwner) && !isPending)
              PopupMenuButton<MemberAdminAction>(
                icon: const Icon(Icons.more_horiz, color: _muted),
                position: PopupMenuPosition.under,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: onAdminAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: MemberAdminAction.viewProfile,
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 18, color: _ink),
                        SizedBox(width: 10),
                        Text('View profile'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: MemberAdminAction.remove,
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_remove_outlined,
                          size: 18,
                          color: Colors.red.shade400,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Remove from club',
                          style: TextStyle(color: Colors.red.shade400),
                        ),
                      ],
                    ),
                  ),
                  //Block option only for admin/owner to block members
                  PopupMenuItem(
                    value: MemberAdminAction.block,
                    child: Row(
                      children: [
                        Icon(Icons.block, size: 18, color: Colors.red.shade400),
                        const SizedBox(width: 10),
                        Text(
                          'Block user',
                          style: TextStyle(color: Colors.red.shade400),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else if (!isPending)
              const Icon(Icons.chevron_right, size: 18, color: _muted),
          ],
        ),
      ),
    );
  }
}

class BlockedMemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback onUnblock;

  const BlockedMemberRow({super.key, required this.member, required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    final name = (member['name'] ?? '') as String;
    final avatar = member['avatar'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Avatar — desaturated look via grey background
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: (avatar != null && avatar.isNotEmpty)
                ? NetworkImage(avatar)
                : null,
            child: (avatar == null || avatar.isEmpty)
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),

          // Name + blocked badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Blocked',
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Unblock action
          TextButton(
            onPressed: onUnblock,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC4A062),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Unblock',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String label;
  final bool isPending;
  const _RoleBadge({required this.label, this.isPending = false});

  @override
  Widget build(BuildContext context) {
    final color = isPending ? Colors.orange.shade700 : _gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
