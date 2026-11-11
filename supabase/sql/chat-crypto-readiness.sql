-- ---------------------------------------------------------------------------
-- Who can read a sealed message
-- ---------------------------------------------------------------------------
--
-- WHY THIS EXISTS
--
-- Messages are moving from plain text to AES-GCM envelopes, and the awkward
-- part is that encryption is decided by the SENDER while readability is a
-- property of the RECEIVER. A client that seals a message to somebody on an
-- older build puts `dl1.20261111.<base64>` in their thread permanently --
-- their app reads `content` straight out of this database and has never
-- heard of an envelope. No server switch and no hotfix can undo it, because
-- the damage is in an app that already shipped.
--
-- A minimum-version gate would mean forcing every user to update before
-- anybody gets encryption. This table avoids that: each client records
-- whether it can open an envelope, and a sender seals only when EVERY
-- participant in the thread says yes. Threads convert themselves, oldest
-- adopters first, and a user who never updates simply keeps plaintext
-- instead of having their chat broken.
--
-- WHY A FLAG CAN ONLY EVER GO UP
--
-- The dangerous direction is believing somebody can read an envelope when
-- they cannot. That would need a client to go backwards -- to have set the
-- flag and then be running an older build -- which the app stores do not
-- allow. So a cached "yes" cannot rot into a wrong answer, which is what
-- makes it safe for the app to cache this aggressively.
--
-- The opposite staleness is harmless: a "no" that is out of date only means
-- a thread keeps sending plaintext slightly longer than it had to.
--
-- WHY EVERYONE CAN READ THE WHOLE TABLE
--
-- It holds no private information -- a user id and a boolean saying which
-- app version they are roughly on. A sender has to check people they may
-- not yet share a conversation row with (the row is created on the first
-- message), so narrowing SELECT to "people I am in a thread with" would
-- break the first message of every new conversation.
--
-- WHAT SOMEBODY COULD DO BY LYING
--
-- Writes are restricted to your own row, so the only lies available are
-- about yourself. Clearing your own flag makes others send you plaintext;
-- setting it on an old build makes your own messages unreadable to you.
-- Both are self-inflicted, and neither exposes anybody else's messages --
-- you still cannot read a thread you are not in, and the key is handed out
-- by WordPress, not by this table.
--
-- Run once, in the Supabase SQL editor.
-- ---------------------------------------------------------------------------

create table if not exists public.chat_crypto_readiness (
  -- The WordPress user id as text, which is what conversations.participant_ids
  -- holds and what the JWT carries in `sub`. Not a uuid: auth.uid() is not
  -- the identity this app uses -- see message-reads-rls.sql.
  user_id    text primary key,

  -- Whether this user's app can OPEN an envelope. Named for the capability
  -- rather than a version number on purpose: the question a sender asks is
  -- "can they read this", and a version would have to be re-interpreted
  -- every time the rule changed.
  can_read   boolean not null default false,

  -- Only ever for looking at by hand -- "how far has adoption got" -- and
  -- never read by the sending decision. Nullable so an older client that
  -- does not send it still counts.
  app_build  text,

  updated_at timestamptz not null default now()
);

alter table public.chat_crypto_readiness enable row level security;

-- Readable by anybody signed in. See the note above on why this is not
-- narrowed to shared conversations.
drop policy if exists chat_crypto_readiness_select on public.chat_crypto_readiness;
create policy chat_crypto_readiness_select
  on public.chat_crypto_readiness
  for select
  to authenticated
  using (true);

-- Writable only for yourself. `sub` is the WordPress user id the token
-- exchange puts in the JWT.
drop policy if exists chat_crypto_readiness_insert on public.chat_crypto_readiness;
create policy chat_crypto_readiness_insert
  on public.chat_crypto_readiness
  for insert
  to authenticated
  with check (user_id = auth.jwt() ->> 'sub');

drop policy if exists chat_crypto_readiness_update on public.chat_crypto_readiness;
create policy chat_crypto_readiness_update
  on public.chat_crypto_readiness
  for update
  to authenticated
  using      (user_id = auth.jwt() ->> 'sub')
  with check (user_id = auth.jwt() ->> 'sub');

-- Deliberately no DELETE policy. Nothing should be removing these rows, and
-- a missing row already means "cannot read" -- so deletion buys nothing and
-- only creates a way to lose adoption state.

-- ---------------------------------------------------------------------------
-- Checking adoption later
-- ---------------------------------------------------------------------------
--
--   select count(*) filter (where can_read) as ready, count(*) as total
--   from public.chat_crypto_readiness;
--
-- And the question that actually matters before turning the global flag on
-- or backfilling history -- how many ACTIVE conversations can be sealed:
--
--   select count(*) filter (where ready) as sealable, count(*) as total
--   from (
--     select c.id,
--            bool_and(coalesce(r.can_read, false)) as ready
--     from public.conversations c
--     cross join lateral unnest(c.participant_ids) as p(user_id)
--     left join public.chat_crypto_readiness r on r.user_id = p.user_id
--     where c.updated_at > now() - interval '30 days'
--     group by c.id
--   ) s;
-- ---------------------------------------------------------------------------
