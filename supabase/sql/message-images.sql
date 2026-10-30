-- ---------------------------------------------------------------------------
-- A photograph in a message
-- ---------------------------------------------------------------------------
--
-- One column. A message carries at most one image, so a column is the
-- honest shape — a media table would promise many and deliver one, and
-- every read would grow a join for a field that is null on most rows.
--
-- It holds a finished Cloudflare delivery URL, not an image id. Same
-- reason as conversations.group_image: PHP turns ids into URLs with
-- get_cloudflare_media_url and Postgres cannot call it. The vehicle
-- tables store bare ids because PHP reads those; these do not.
--
-- NO VIDEO. Not a limitation to be lifted later without thinking: a
-- video needs a poster frame, a duration, a size limit, a transcode and
-- a player, and every one of those is a decision this column cannot
-- hold. When video comes it wants its own shape, not a longer URL.
--
-- ---------------------------------------------------------------------------
-- 1. BEFORE
-- ---------------------------------------------------------------------------

-- What is on messages already. Section 2 adds to this; it does not
-- reshape anything, and the app tolerates the column being absent.
select column_name, data_type, is_nullable
from   information_schema.columns
where  table_schema = 'public'
and    table_name   = 'messages'
order  by ordinal_position;


-- ---------------------------------------------------------------------------
-- 2. THE CHANGE
-- ---------------------------------------------------------------------------

alter table public.messages
  add column if not exists image_url text;

comment on column public.messages.image_url is
  'Cloudflare Images delivery URL for a photo sent in this message. A '
  'finished URL rather than an image id: Postgres cannot call '
  'get_cloudflare_media_url. One per message, images only — see '
  'supabase/sql/message-images.sql. Null for text-only messages.';


-- ---------------------------------------------------------------------------
-- 3. WHAT ALREADY COVERS IT
-- ---------------------------------------------------------------------------
--
-- Nothing new is needed for permissions. Whatever policy lets somebody
-- insert a message already lets them insert this column with it, and the
-- delete window policy already blanks the row -- except that it blanks
-- `content` and knows nothing about this.
--
-- So the app clears both when a message is taken back. Worth saying out
-- loud because a tombstone that still carries its photograph is not a
-- deleted message, and nothing in the database will catch that:
--
--   update messages
--      set deleted_at = now(), content = '', image_url = null
--    where id = ...
--
-- If a trigger ever enforces the soft delete rather than the app, this
-- is the column it will be easiest to forget.


-- ---------------------------------------------------------------------------
-- 4. AFTER
-- ---------------------------------------------------------------------------

select column_name, data_type
from   information_schema.columns
where  table_schema = 'public'
and    table_name = 'messages'
and    column_name = 'image_url';
