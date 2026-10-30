-- ---------------------------------------------------------------------------
-- Blocking, enforced at the point of sending
-- ---------------------------------------------------------------------------
--
-- WHY THIS FILE EXISTS AT ALL, GIVEN ce_user_blocks
--
-- A block lives in WordPress -- php-api/sql/moderation.sql explains why: it
-- is about a PERSON, and the feed, comments, tagging and the profile are all
-- WordPress and all need to read it.
--
-- But a message is not inserted by WordPress. The app writes it straight to
-- PostgREST, and Postgres cannot see a MySQL table. So the block that stops
-- someone sending has to exist HERE, as a mirror, or it does not stop
-- anything. Until this file ran, blocking only suppressed the push
-- notification: the message still landed in the thread.
--
-- WordPress stays the source of truth. endpoints/moderation.php writes
-- ce_user_blocks first and then mirrors the row here, and GET
-- /moderation/blocks re-pushes anything missing, so a failed mirror heals
-- rather than staying broken.
--
-- WHAT A BLOCK STOPS, AND WHAT IT DOES NOT
--
-- One-to-one only. Blocking someone does not throw them out of a group you
-- are both in, and does not stop you posting in it -- that is how Instagram,
-- WhatsApp and iMessage all behave, and the alternative is that blocking one
-- person silently removes you from a nine-person thread.
--
-- It is symmetrical. If either of you blocked the other, neither can send.
-- Storing one row and checking both columns is what makes that true without
-- two rows that can drift apart.
--
-- ---------------------------------------------------------------------------
-- 1. BEFORE
-- ---------------------------------------------------------------------------

-- (a) Confirm the shape this file assumes: participant_ids as text[], and
--     ids held as the WordPress user id in text. If participant_ids comes
--     back as jsonb, see the note above section 3.
select column_name, data_type, udt_name
from   information_schema.columns
where  table_schema = 'public'
and    table_name   = 'conversations'
and    column_name in ('id', 'participant_ids', 'is_group');

-- (b) The INSERT policies already on messages. The one added in section 3 is
--     RESTRICTIVE, so it ANDs with whatever is here rather than replacing
--     it. Read that list before and after.
select polname, polpermissive, pg_get_expr(polwithcheck, polrelid) as with_check
from   pg_policy
where  polrelid = 'public.messages'::regclass
and    polcmd in ('a', '*');


-- ---------------------------------------------------------------------------
-- 2. THE MIRROR
-- ---------------------------------------------------------------------------

create table if not exists public.user_blocks (
  -- WordPress user ids, as text, to match auth.jwt() ->> 'sub' and
  -- conversations.participant_ids without a cast in the hot path.
  user_id    text not null,
  blocked_id text not null,

  created_at timestamptz not null default now(),

  -- Blocking twice is one block. The mirror push relies on this to be
  -- idempotent.
  primary key (user_id, blocked_id)
);

-- "Has anyone in this conversation blocked me, or have I blocked them" is
-- asked on every send, in both directions, so both columns need an index.
-- The primary key already covers user_id.
create index if not exists user_blocks_blocked_idx
  on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;

-- Nothing in the app writes this table. It is mirrored in with the
-- service_role key, which bypasses RLS, so there is deliberately no insert,
-- update or delete policy: a client that could write here could unblock
-- itself.
drop policy if exists "user_blocks: read my own" on public.user_blocks;

-- Readable only in the direction that is safe to know. You may see who YOU
-- blocked; you may not see who blocked you. Every platform hides the second
-- one, because knowing is what provokes the next account.
create policy "user_blocks: read my own"
  on public.user_blocks
  for select
  to authenticated
  using (user_id = auth.jwt() ->> 'sub');


-- ---------------------------------------------------------------------------
-- 3. THE CHECK
-- ---------------------------------------------------------------------------
--
-- Written for participant_ids as text[]. If 1(a) says jsonb, swap
--   b.blocked_id = any(c.participant_ids)
-- for
--   c.participant_ids ? b.blocked_id
-- in both branches.

create or replace function public.dl_send_blocked(
  p_conversation uuid,
  p_sender       text
)
returns boolean
language sql
stable
-- security definer because the caller is `authenticated`, and section 2
-- deliberately does not let them read the rows where someone blocked THEM.
-- Without this the check would see half the table and enforce half the
-- blocks -- the half that matters least.
security definer
set search_path = public
as $fn$
  select exists (
    select 1
      from public.conversations c
      join public.user_blocks   b
        on (
             -- I blocked someone who is in here.
             (b.user_id = p_sender and b.blocked_id = any(c.participant_ids)
              and b.blocked_id <> p_sender)
             or
             -- Someone in here blocked me.
             (b.blocked_id = p_sender and b.user_id = any(c.participant_ids)
              and b.user_id <> p_sender)
           )
     where c.id = p_conversation
       -- One-to-one only. See the header.
       and coalesce(c.is_group, false) = false
  );
$fn$;

revoke all on function public.dl_send_blocked(uuid, text) from public;
grant execute on function public.dl_send_blocked(uuid, text) to authenticated;

drop policy if exists "messages: not to or from a block" on public.messages;

-- AS RESTRICTIVE is the whole point of this policy and the easiest thing to
-- get wrong. Postgres combines PERMISSIVE policies for the same command with
-- OR, so adding an ordinary policy here would WIDEN what may be inserted --
-- it would grant a second way in, not take one away. Restrictive policies
-- are ANDed with the permissive set, and that is the only way to subtract.
create policy "messages: not to or from a block"
  on public.messages
  as restrictive
  for insert
  to authenticated
  with check (
    not public.dl_send_blocked(conversation_id, auth.jwt() ->> 'sub')
  );


-- ---------------------------------------------------------------------------
-- 4. AFTER
-- ---------------------------------------------------------------------------

-- Expect the new row, with polpermissive = false.
select polname, polpermissive, pg_get_expr(polwithcheck, polrelid) as with_check
from   pg_policy
where  polrelid = 'public.messages'::regclass
and    polcmd in ('a', '*');

-- Smoke test with two real ids from a one-to-one conversation. Run as the
-- postgres role, which reads the mirror directly rather than through RLS.
--
--   insert into public.user_blocks (user_id, blocked_id) values ('<a>', '<b>');
--
--   select public.dl_send_blocked('<conversation uuid>', '<a>');  -- t
--   select public.dl_send_blocked('<conversation uuid>', '<b>');  -- t, both ways
--
--   delete from public.user_blocks where user_id = '<a>' and blocked_id = '<b>';
--   select public.dl_send_blocked('<conversation uuid>', '<a>');  -- f


-- ---------------------------------------------------------------------------
-- 5. WHAT THIS DOES NOT DO
-- ---------------------------------------------------------------------------
--
--   * It does not hide history. Messages already sent stay in the thread,
--     the way they do on Instagram. Removing them is a different decision
--     and a destructive one.
--   * It does not stop a group message, by design -- see the header.
--   * It does not stop reactions or read receipts. message_reactions and
--     message_reads want the same restrictive treatment; a block that lets
--     someone keep reacting to your messages is not finished. Noted here
--     rather than done, because each wants its own before and after.
--   * The mirror is eventually consistent. A block applies in WordPress at
--     once and in chat as soon as the push lands; a failed push is retried
--     on the next GET /moderation/blocks.
