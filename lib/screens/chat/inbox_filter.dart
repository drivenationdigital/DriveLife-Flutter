/// The pills above the inbox: All, Unread, Groups.
///
/// A pure predicate in its own file, taking the two facts it needs rather
/// than a ConversationPreview, so the rules can be tested without a
/// Supabase client or a widget tree.
library;

enum InboxFilter {
  all,
  unread,

  /// Group conversations.
  ///
  /// The design calls this pill "Clubs", and it is not — nothing on a
  /// conversation says which club it belongs to, or whether it belongs to
  /// one at all. `is_group` is the only thing that distinguishes these
  /// rows today, so the pill says Groups and means it.
  ///
  /// If club chats become distinguishable — a club_id on conversations,
  /// say — this is the one place that changes: rename the value, and
  /// widen [matchesInboxFilter] to take the new field.
  groups;

  String get label => switch (this) {
    InboxFilter.all => 'All',
    InboxFilter.unread => 'Unread',
    InboxFilter.groups => 'Groups',
  };
}

/// Whether a conversation belongs under [filter].
bool matchesInboxFilter(
  InboxFilter filter, {
  required bool isGroup,
  required int unreadCount,
}) => switch (filter) {
  InboxFilter.all => true,
  InboxFilter.unread => unreadCount > 0,
  InboxFilter.groups => isGroup,
};

/// What the empty state should say when a filter has hidden everything.
///
/// Worth distinguishing from a genuinely empty inbox: "No messages yet"
/// under an Unread pill that is hiding four conversations is a lie, and
/// the way out of it is not obvious unless the copy names the filter.
String emptyInboxMessage(InboxFilter filter) => switch (filter) {
  InboxFilter.all => 'No messages yet',
  InboxFilter.unread => 'Nothing unread',
  InboxFilter.groups => 'No group chats yet',
};
