-- ---------------------------------------------------------------------------
-- get_inbox: return the last message's image and deleted flag
-- ---------------------------------------------------------------------------
--
-- WHY
--
-- The inbox row shows a preview of the last message. For a photo sent
-- without a caption that preview was BLANK — the content is an empty
-- string and the function returns nothing else about the message, so
-- the app had no way to know there was a picture and drew an empty line
-- where the preview goes. A conversation that had just received a photo
-- looked like one that had gone quiet.
--
-- The app now infers it: a last message with no text is treated as a
-- photo, because sendMessage refuses one that is neither text nor
-- image. That inference is right in every case but one — a DELETED last
-- message also has empty content, and reads as "Photo" when it should
-- read as deleted.
--
-- Returning these two columns removes the guess.
--
-- ---------------------------------------------------------------------------
-- 1. BEFORE — read this before changing anything
-- ---------------------------------------------------------------------------
--
-- This file cannot give you a finished CREATE OR REPLACE, because the
-- current body of get_inbox is not in this repo — it was written in the
-- Supabase dashboard. Print it, add the two columns to the copy you get
-- back, and run that. Guessing at the body would quietly drop whatever
-- else it does.

select pg_get_functiondef(p.oid)
from   pg_proc p
join   pg_namespace n on n.oid = p.pronamespace
where  n.nspname = 'public'
and    p.proname = 'get_inbox';

-- Its current output columns, which is the list to extend:
select t.*
from   pg_proc p
join   pg_namespace n on n.oid = p.pronamespace
cross  join lateral unnest(p.proallargtypes, p.proargmodes, p.proargnames)
         as t(type_oid, mode, name)
where  n.nspname = 'public'
and    p.proname = 'get_inbox'
and    t.mode = 't';


-- ---------------------------------------------------------------------------
-- 2. WHAT TO ADD
-- ---------------------------------------------------------------------------
--
-- Two columns on the RETURNS TABLE, alongside last_message_content:
--
--     last_message_image   text,
--     last_message_deleted timestamptz,
--
-- And in the body, wherever last_message_content is selected from the
-- newest message, take these from the SAME row:
--
--     m.image_url   as last_message_image,
--     m.deleted_at  as last_message_deleted,
--
-- The app reads both with `as String?` / tryParse and treats an absent
-- key as "not told", so it keeps working on the old function and
-- becomes exact on the new one. There is no coordinated deploy here —
-- ship whichever order suits.


-- ---------------------------------------------------------------------------
-- 3. AFTER
-- ---------------------------------------------------------------------------

-- Expect the two new names in the list.
select t.name
from   pg_proc p
join   pg_namespace n on n.oid = p.pronamespace
cross  join lateral unnest(p.proallargtypes, p.proargmodes, p.proargnames)
         as t(type_oid, mode, name)
where  n.nspname = 'public'
and    p.proname = 'get_inbox'
and    t.mode = 't';

-- And a real call, as a signed-in user id:
--
--   select * from get_inbox('<wordpress user id>');
--
-- A conversation whose last message was a photo should now come back
-- with last_message_image set and last_message_content empty.


-- ---------------------------------------------------------------------------
-- 4. THE OTHER COLUMN THIS FUNCTION STILL OWES
-- ---------------------------------------------------------------------------
--
-- group_image. The conversations TABLE has it; this function does not
-- return it, so the app runs a second query against conversations after
-- every inbox load purely to fill it in — see _withGroupImages in
-- SupabaseClasses.dart. Adding
--
--     c.group_image as group_image,
--
-- while you are in here removes that extra round trip, and the Dart
-- fallback can then be deleted.
