-- ---------------------------------------------------------------------------
-- Which tables Realtime is allowed to broadcast
-- ---------------------------------------------------------------------------
--
-- Subscribing in the app is only half of it. Postgres only streams changes
-- for tables in the `supabase_realtime` publication, and a binding to a
-- table that is NOT in it does not quietly do nothing -- it fails.
--
-- WHY THIS EXPLAINS TWO SEPARATE BUGS
--
-- The failure is per CHANNEL, not per binding. The client sends every
-- binding in one join, the server validates them together, and one bad
-- table puts the whole channel into CHANNEL_ERROR. Every other binding on
-- that channel dies with it.
--
--   * reactionStream() binds message_reactions. Not published, so the
--     channel errors and no reaction ever arrives.
--
--   * conversationUpdates() binds messages (insert), messages (update)
--     AND conversations (update). conversations is not published, so that
--     channel errors too -- and takes the two `messages` bindings with
--     it. That is why the inbox did not update live while the open thread
--     did, despite both of them listening to `messages`.
--
-- The second one is the useful lesson: the inbox looked like a `messages`
-- problem and was a `conversations` problem.
--
-- ---------------------------------------------------------------------------
-- 1. BEFORE
-- ---------------------------------------------------------------------------

-- What is published today. Expect `messages` and little else -- it was
-- added by hand in the dashboard when messaging was built, which is why
-- nothing in this repo records it.
select schemaname, tablename
from   pg_publication_tables
where  pubname = 'supabase_realtime'
order  by tablename;

-- Replica identity per table. 'd' is default (primary key only), 'f' is
-- full. Section 3 explains why that matters for deletes.
select c.relname,
       case c.relreplident
         when 'd' then 'default (primary key only)'
         when 'f' then 'full'
         when 'n' then 'nothing'
         when 'i' then 'index'
       end as replica_identity
from   pg_class c
join   pg_namespace n on n.oid = c.relnamespace
where  n.nspname = 'public'
and    c.relname in ('messages', 'conversations', 'message_reactions',
                     'message_reads');


-- ---------------------------------------------------------------------------
-- 2. PUBLISH THEM
-- ---------------------------------------------------------------------------
--
-- ALTER PUBLICATION ... ADD TABLE errors if the table is already a member,
-- and there is no IF NOT EXISTS for it, so each one is guarded. Run the
-- whole block; the guards make it safe to re-run.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table public.conversations;
  end if;

  -- Belt and braces. The open thread already works, so this is almost
  -- certainly already a member -- the guard makes saying so cost nothing.
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end
$$;


-- ---------------------------------------------------------------------------
-- 3. DELETES NEED REPLICA IDENTITY FULL
-- ---------------------------------------------------------------------------
--
-- Publishing message_reactions makes an ADDED reaction arrive. A REMOVED
-- one still will not, and the reason is worth knowing because it is
-- invisible from the client.
--
-- With the default replica identity, Postgres puts ONLY THE PRIMARY KEY in
-- the WAL record for a delete. Realtime therefore receives a delete whose
-- payload is {id: ...} and nothing else -- so the subscription's filter,
--
--     conversation_id = eq.<this conversation>
--
-- cannot be evaluated against it, and the event is dropped before it ever
-- reaches the app. The reaction vanishes for whoever removed it and stays
-- on everybody else's screen until they reopen the thread.
--
-- REPLICA IDENTITY FULL writes the whole old row instead, so the filter
-- has a conversation_id to match. The cost is a larger WAL record per
-- update and delete, which on a table of a few dozen rows per thread is
-- not a consideration.

alter table public.message_reactions replica identity full;

-- Not done for `messages`: its subscriptions are insert and update only,
-- and a delete there is a soft delete -- deleteMessage() writes deleted_at
-- and blanks the content, which is an UPDATE and already carries the whole
-- new row. Turning this on for the big table would widen every WAL record
-- for no behaviour gained.


-- ---------------------------------------------------------------------------
-- 4. AFTER
-- ---------------------------------------------------------------------------

-- Expect conversations, message_reactions and messages.
select schemaname, tablename
from   pg_publication_tables
where  pubname = 'supabase_realtime'
order  by tablename;

-- Expect message_reactions = full.
select c.relname,
       case c.relreplident
         when 'd' then 'default (primary key only)'
         when 'f' then 'full'
         else c.relreplident::text
       end as replica_identity
from   pg_class c
join   pg_namespace n on n.oid = c.relnamespace
where  n.nspname = 'public'
and    c.relname in ('messages', 'conversations', 'message_reactions');


-- ---------------------------------------------------------------------------
-- 5. NOTES
-- ---------------------------------------------------------------------------
--
--   * Realtime still applies RLS to what it sends, using the token the
--     channel was subscribed with. A channel joined before
--     SupabaseSession.ensure() has applied the user's token is joined as
--     anon, and an anon channel on an RLS-protected table is subscribed
--     and permanently silent. Publishing the table does not change that;
--     the two failure modes look identical from the app and are fixed in
--     different places.
--
--   * message_reads is deliberately NOT published. Nothing subscribes to
--     it -- read state arrives with the message rows on refresh -- and
--     publishing a table nothing listens to is WAL traffic for nobody. If
--     live read receipts are wanted later, this is where that starts.
--
--   * Adding a table here is a change nothing in the repo would otherwise
--     record, which is how `messages` came to be published with no trace
--     of who did it or when. Anything added by hand in the dashboard from
--     now on should be added to this file instead.
