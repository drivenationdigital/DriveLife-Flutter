-- ---------------------------------------------------------------------------
-- Moderation flags on a message
-- ---------------------------------------------------------------------------
--
-- Tier two of the content filter. Tier one is lib/services/content_filter.dart,
-- a word list that runs on the reader's device when the bubble is drawn --
-- instant, free, offline, and blind to anything not in the list.
--
-- These two columns are where the other half lands: a Gemini pass in
-- chat_webhook.php that reads the message after it is inserted and decides
-- whether it is cruel, threatening or sexual in a way no list could catch.
--
-- WHY AFTER THE INSERT, WHICH IS A REAL WEAKNESS
--
-- The app writes messages straight to PostgREST. WordPress never sees one
-- at send time, so there is no point at which a scan could run BEFORE
-- delivery without routing every message through WordPress and adding a
-- Gemini round trip to the latency of every single send.
--
-- So the scan runs in the webhook, a second or two behind, and the flag
-- arrives as an UPDATE that realtime pushes to the open thread. There is a
-- window in which an unflagged message is readable. The word list is what
-- covers that window for the obvious cases; for the subtle ones the honest
-- description is that the warning may appear a moment after the message.
--
-- ---------------------------------------------------------------------------
-- 1. BEFORE
-- ---------------------------------------------------------------------------

select column_name, data_type
from   information_schema.columns
where  table_schema = 'public'
and    table_name   = 'messages'
order  by ordinal_position;


-- ---------------------------------------------------------------------------
-- 2. THE COLUMNS
-- ---------------------------------------------------------------------------

alter table public.messages
  add column if not exists flagged_at  timestamptz,
  add column if not exists flag_reason text;

comment on column public.messages.flagged_at is
  'Set by the moderation scan in chat_webhook.php. Non-null means the '
  'client should hide the message behind a warning.';

comment on column public.messages.flag_reason is
  'A short phrase for the warning card, e.g. "a threat" or "sexual '
  'content". Never the message text itself.';

-- Partial, because flagged messages are a tiny fraction of the table and
-- the only query that wants them is the review queue -- "what has been
-- flagged lately". An index over the whole column would be mostly nulls.
create index if not exists messages_flagged_idx
  on public.messages (flagged_at desc)
  where flagged_at is not null;


-- ---------------------------------------------------------------------------
-- 3. WHO MAY WRITE THEM
-- ---------------------------------------------------------------------------
--
-- Nobody, through the app. The webhook writes these with the service_role
-- key, which bypasses RLS, so no policy is needed to let it through.
--
-- What DOES need checking is that the existing UPDATE policy on messages
-- cannot be used to clear a flag. The delete policy added in
-- message-reactions-and-delete.sql lets a sender update their own message
-- inside the delete window -- and PostgREST will happily send
-- flagged_at = null in that same request if a modified client asks it to.
--
-- Run this to see what the UPDATE policies currently allow:

select polname,
       polpermissive,
       pg_get_expr(polqual,      polrelid) as using_expr,
       pg_get_expr(polwithcheck, polrelid) as with_check
from   pg_policy
where  polrelid = 'public.messages'::regclass
and    polcmd in ('w', '*');

-- Column-level privileges are the fix, and they are checked BEFORE RLS:
-- revoking table-level update means no amount of policy matching lets a
-- client clear its own flag. The grant that follows re-permits exactly
-- the columns the app legitimately writes.
--
-- THE LIST BELOW IS THE WHOLE LIST. Every UPDATE the app makes to this
-- table must appear here or it fails with
--
--   PostgrestException(message: permission denied for table messages,
--                      code: 42501)
--
-- which names the TABLE and not the column, so it tells you nothing
-- about which write broke. There are three writes to public.messages in
-- the app, all in lib/screens/chat/SupabaseClasses.dart:
--
--   insert       sendMessage()   -- not affected, INSERT is untouched
--   deleted_at   deleteMessage() -- plus content and image_url, blanked
--   read_at      markAsRead()    -- the easy one to forget, because it
--                                   is a read receipt rather than an
--                                   edit, and nothing in the UI calls it
--
-- Grep `from('messages')` for `.update(` before changing this.

revoke update on public.messages from authenticated;

grant update (content, image_url, deleted_at, read_at)
  on public.messages to authenticated;


-- ---------------------------------------------------------------------------
-- 4. AFTER
-- ---------------------------------------------------------------------------

-- Expect flagged_at and flag_reason.
select column_name, data_type
from   information_schema.columns
where  table_schema = 'public'
and    table_name   = 'messages'
and    column_name in ('flagged_at', 'flag_reason');

-- Expect exactly content, deleted_at, image_url and read_at -- four rows,
-- and NOT flagged_at or flag_reason. If a row is missing here, the write
-- that needs it fails at runtime with a 42501 naming only the table.
select grantee, privilege_type, column_name
from   information_schema.column_privileges
where  table_schema = 'public'
and    table_name   = 'messages'
and    grantee      = 'authenticated'
and    privilege_type = 'UPDATE'
order  by column_name;

-- Sanity check, as the postgres role:
--
--   update public.messages
--      set flagged_at = now(), flag_reason = 'a threat'
--    where id = '<some message uuid>';
--
-- The open thread should veil it within a second or two, because
-- messageStream() now binds UPDATE as well as INSERT. If it does not,
-- check that `messages` is in the supabase_realtime publication --
-- see realtime-publication.sql.


-- ---------------------------------------------------------------------------
-- 5. WHAT THIS DOES NOT DO
-- ---------------------------------------------------------------------------
--
--   * It does not block delivery. A flagged message is delivered and then
--     covered, not withheld. Withholding needs the send to go through
--     WordPress; see the header.
--   * It does not notify anybody. A flag is not a report -- nothing lands
--     in ce_user_reports unless a person chooses to report it. Whether a
--     flagged message should auto-report at some severity is a product
--     decision and deliberately not made here.
--   * It does not act on a repeat offender. The data to do it is now
--     present -- count flagged_at per sender_id over a window -- but
--     nothing counts it.
