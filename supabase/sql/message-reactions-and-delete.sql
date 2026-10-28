-- ---------------------------------------------------------------------------
-- Reactions, and taking a message back
-- ---------------------------------------------------------------------------
--
-- One new table and one new column.
--
--   message_reactions   who put which emoji on which message
--   messages.deleted_at when the sender took it back, null while it stands
--
-- Two things here are decisions rather than mechanics, and both are made
-- in the database on purpose.
--
-- THE DELETE WINDOW IS A POLICY, NOT A BUTTON
--
-- The app will only offer "Delete" on a message inside the window, but
-- that is a courtesy to the user, not a control. Anyone holding the
-- publishable key -- which is in every installed copy of the app -- can
-- send the update themselves. So the window lives in the USING clause
-- below, where it is the database refusing rather than the client not
-- asking.
--
-- IT IS A SOFT DELETE
--
-- deleted_at, not DELETE. A hard delete leaves holes in every other
-- client's MessageCache, gives the realtime subscription nothing to push,
-- and makes "This message was deleted" impossible to draw. The content is
-- blanked in the same statement, so the row that remains is a tombstone
-- and not a copy of what was said.
--
-- ---------------------------------------------------------------------------
-- 1. BEFORE -- read-only. Two things need checking first.
-- ---------------------------------------------------------------------------

-- (a) How is conversation membership stored? The reaction policies have to
--     ask "is this person in this conversation", and the answer is written
--     against conversations.participant_ids. If that is text[] the
--     policies below work as written; if it is jsonb they need
--     `participant_ids ? auth.jwt() ->> 'sub'` instead.
select  column_name, data_type, udt_name
from    information_schema.columns
where   table_schema = 'public'
and     table_name   = 'conversations'
order by ordinal_position;

-- (b) What do the existing policies look like? Whatever `messages` does
--     to express "mine", this should do the same way. auth.uid() will not
--     be it -- that casts `sub` to uuid and supabase_auth_bridge.php puts
--     a numeric WordPress id there -- so expect auth.jwt() ->> 'sub'.
select  tablename, policyname, cmd, roles, qual, with_check
from    pg_policies
where   schemaname = 'public'
and     tablename in ('messages', 'conversations')
order by tablename, policyname;


-- ---------------------------------------------------------------------------
-- 2. THE CHANGE
-- ---------------------------------------------------------------------------

alter table public.messages
  add column if not exists deleted_at timestamptz;

create table if not exists public.message_reactions (
  id              uuid primary key default gen_random_uuid(),
  message_id      uuid not null references public.messages(id) on delete cascade,

  -- Denormalised, and not redundant. Supabase realtime filters a
  -- subscription on one column of one table and cannot join, so without
  -- this there is no way to say "reactions in this conversation" and the
  -- ticks never live-update. The cascade above keeps it honest.
  conversation_id uuid not null references public.conversations(id) on delete cascade,

  -- A WordPress user id as text, matching messages.sender_id and the
  -- `sub` claim the bridge mints.
  user_id         text not null,
  emoji           text not null,
  created_at      timestamptz not null default now(),

  -- One of each emoji per person per message. Tapping the same one again
  -- deletes the row rather than adding a second.
  unique (message_id, user_id, emoji)
);

-- Reading a message's reactions, and the realtime filter, both go by
-- conversation.
create index if not exists message_reactions_conversation_idx
  on public.message_reactions (conversation_id, message_id);

alter table public.message_reactions enable row level security;


-- ---------------------------------------------------------------------------
-- 3. POLICIES
-- ---------------------------------------------------------------------------
--
-- Written for participant_ids as text[]. If 1(a) says jsonb, swap
--   auth.jwt() ->> 'sub' = any(c.participant_ids)
-- for
--   c.participant_ids ? (auth.jwt() ->> 'sub')
-- in all three.

-- You may see reactions on conversations you are in. Not "reactions on
-- your own messages" -- everyone in a thread sees everyone's.
create policy "reactions: read in my conversations"
  on public.message_reactions
  for select
  to authenticated
  using (
    exists (
      select 1 from public.conversations c
      where c.id = message_reactions.conversation_id
        and auth.jwt() ->> 'sub' = any(c.participant_ids)
    )
  );

-- You may add your own, in a conversation you are in. Both halves matter:
-- without the membership check anyone could react to any message whose id
-- they could guess, and without the user_id check they could react as
-- somebody else.
create policy "reactions: add my own"
  on public.message_reactions
  for insert
  to authenticated
  with check (
    user_id = auth.jwt() ->> 'sub'
    and exists (
      select 1 from public.conversations c
      where c.id = message_reactions.conversation_id
        and auth.jwt() ->> 'sub' = any(c.participant_ids)
    )
  );

-- And remove your own, with no time limit. Taking back a thumbs-up is not
-- the same act as taking back a sentence.
create policy "reactions: remove my own"
  on public.message_reactions
  for delete
  to authenticated
  using (user_id = auth.jwt() ->> 'sub');


-- The delete window. 15 minutes, in one place.
--
-- WhatsApp allows about an hour, Instagram allows your own messages
-- forever. Fifteen is long enough to catch the message you regret and
-- short enough that a conversation somebody else has read stays a record
-- of what was said. Change the interval here and the app follows -- it
-- reads the same number to decide whether to offer the option.
create policy "messages: delete my own, briefly"
  on public.messages
  for update
  to authenticated
  using (
    sender_id = auth.jwt() ->> 'sub'
    and created_at > now() - interval '15 minutes'
  )
  with check (
    sender_id = auth.jwt() ->> 'sub'
  );


-- ---------------------------------------------------------------------------
-- 4. AFTER
-- ---------------------------------------------------------------------------

select  c.relname, c.relrowsecurity as rls_enabled,
        (select count(*) from pg_policies p
          where p.schemaname = 'public' and p.tablename = c.relname)
          as policies
from    pg_class c
join    pg_namespace n on n.oid = c.relnamespace
where   n.nspname = 'public'
and     c.relname in ('messages', 'message_reactions');

-- The window, from outside. Signed in as a normal user, this should
-- update 1 row for something sent a minute ago and 0 rows for something
-- sent an hour ago -- with no error either way, because RLS filters
-- rather than refuses.
--
--   update messages set deleted_at = now(), content = ''
--    where id = '<one of yours, recent>';
--
--   update messages set deleted_at = now(), content = ''
--    where id = '<one of yours, older than 15 minutes>';
--
-- If the second one reports a row, the policy is not doing its job and
-- the app's own check is all that stands between a user and editing
-- their history.


-- ---------------------------------------------------------------------------
-- 5. WHILE YOU ARE HERE
-- ---------------------------------------------------------------------------
--
-- public.message_reads still has no RLS -- see message-reads-rls.sql. And
-- the service_role key in chat_webhook.php bypasses every policy written
-- above, so none of this is load-bearing until that is rotated.
