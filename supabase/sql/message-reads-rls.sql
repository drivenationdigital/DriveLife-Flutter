-- ---------------------------------------------------------------------------
-- public.message_reads has no row level security
-- ---------------------------------------------------------------------------
--
-- READ FIRST: none of this holds while the project's JWT secret is
-- readable. php-api/endpoints/supabase_auth_bridge.php line 33 defines
-- SUPABASE_JWT_SECRET in the file itself, against its own install notes.
-- Anyone holding that string can sign a token claiming
-- "role": "service_role", and service_role bypasses row level security on
-- every table in the project. Until it is moved to wp-config.php AND
-- rotated in the Supabase dashboard, the policies below are a lock on a
-- door with the key taped to it.
--
-- Rotating invalidates every token already issued. The app re-fetches on
-- its own -- SupabaseTokenManager asks the bridge again -- so the cost is
-- one round trip per signed-in user, not a logout.
--
-- Reported by the Supabase database linter, 2026-10-28:
--
--   rls_disabled_in_public / ERROR / EXTERNAL
--   Table `public.message_reads` is public, but RLS has not been enabled.
--
-- What that means here, specifically.
--
-- Every table in the `public` schema is served by PostgREST at
-- https://hekpfyxiduypovcvwffm.supabase.co/rest/v1/<table>. Reaching it
-- needs nothing but the publishable key -- which is, correctly, not a
-- secret: it is in lib/screens/chat/SupabaseClasses.dart and in every copy
-- of the app anybody has installed. The thing that stops a stranger with
-- that key reading a table is row level security, and on this one table
-- there is none. So right now that URL will hand anyone the whole of
-- message_reads, and accept their writes to it.
--
-- It is not the worst table it could have been. Message bodies live in
-- `messages`, which the linter did not flag, so no conversation content is
-- exposed by this. What is exposed is the metadata: who has read whose
-- messages and when. Across the whole table that is a social graph and an
-- activity timeline for every user of the app -- who talks to whom, and
-- when each of them was last awake. Writable, too: receipts can be forged
-- or removed.
--
-- Treat it as a privacy breach to close promptly rather than an emergency
-- to close tonight -- unless the queries in section 1 show the table has
-- real rows in it, in which case assume it has been readable for as long
-- as it has existed.
--
-- ---------------------------------------------------------------------------
-- 1. BEFORE -- read-only. Run this first and keep the output.
-- ---------------------------------------------------------------------------
--
-- Four things need to be known before anything is changed, and three of
-- them cannot be read from the app's source.

-- (a) Is message_reads really the only one? The linter mail showed a
--     single row, but it is a digest and may have been truncated.
select  c.relname                as table_name,
        c.relrowsecurity         as rls_enabled,
        c.relforcerowsecurity    as rls_forced
from    pg_class c
join    pg_namespace n on n.oid = c.relnamespace
where   n.nspname = 'public'
and     c.relkind = 'r'
order by c.relrowsecurity asc, c.relname;

-- (b) What is in it? The policies in section 3 are written against column
--     names this file is guessing at -- user_id and conversation_id. If
--     they are called something else, section 3 needs editing before it
--     will run, let alone be correct.
select  column_name, data_type, is_nullable
from    information_schema.columns
where   table_schema = 'public'
and     table_name   = 'message_reads'
order by ordinal_position;

-- (c) How do the tables that DO have RLS express "this row is mine"?
--     Whatever `conversations` and `messages` do, message_reads should do
--     the same way. Note that auth.uid() cannot be it: that function casts
--     the `sub` claim to uuid, and supabase_auth_bridge.php puts a numeric
--     WordPress user id in there. Expect to see auth.jwt() ->> 'sub'.
select  tablename, policyname, cmd, roles, qual, with_check
from    pg_policies
where   schemaname = 'public'
order by tablename, policyname;

-- (d) Do the RPCs bypass RLS? This decides whether section 2 is safe.
--     SECURITY DEFINER (prosecdef = true) runs as the function's owner and
--     ignores RLS. SECURITY INVOKER -- which is the DEFAULT, and so the
--     likely answer -- runs as the caller, and will start obeying whatever
--     is enabled below.
select  p.proname, p.prosecdef as security_definer
from    pg_proc p
join    pg_namespace n on n.oid = p.pronamespace
where   n.nspname = 'public'
and     p.proname in ('get_inbox', 'leave_group');

-- (e) How much is in there, i.e. how much has been readable.
select count(*) as rows_exposed from public.message_reads;


-- ---------------------------------------------------------------------------
-- 2. THE CHANGE -- stop the bleeding
-- ---------------------------------------------------------------------------
--
-- Enabling RLS with no policies at all denies everything to `anon` and
-- `authenticated`. That sounds drastic and here it probably is not, because
-- nothing in the app touches this table:
--
--   * no .from('message_reads') anywhere in lib/ -- the app's only direct
--     Supabase tables are conversations, messages and conversation_deletes
--   * no realtime subscription to it -- the two channels in
--     SupabaseClasses.dart listen to `messages` and `conversations` only
--   * read state for a one-to-one chat is messages.read_at, which is a
--     column on another table entirely
--
-- So message_reads is reached, if at all, by get_inbox / leave_group or by
-- a trigger. Whether this line breaks them is exactly question 1(d).
--
--   prosecdef = true  -> they bypass RLS, this is safe, you are done
--   prosecdef = false -> they will start being filtered; do section 3 too,
--                        or make the function SECURITY DEFINER
--
-- Either way, enable it. A table with RLS on and no policy is closed; a
-- table with RLS off is open to the internet.

alter table public.message_reads enable row level security;

-- Belt and braces, and arguably the better fix on its own: if nothing is
-- meant to reach this table over the REST API, take it out of PostgREST's
-- reach entirely rather than relying on a policy to say no. Uncomment once
-- 1(d) says the RPCs are SECURITY DEFINER.
--
-- revoke all on public.message_reads from anon, authenticated;


-- ---------------------------------------------------------------------------
-- 3. POLICIES -- only if something really does need direct access
-- ---------------------------------------------------------------------------
--
-- DO NOT RUN THIS BLIND. The column names below are inferred from the
-- table's name and from how the rest of the schema is used; 1(b) will say
-- whether they are right. A policy written against the wrong column either
-- fails to create or -- worse -- creates and silently allows more than it
-- should.
--
-- The shape, assuming message_reads(user_id, conversation_id, ...):
-- a receipt is yours if it has your id on it, and you may only write your
-- own. `sub` is a WordPress user id as text, so the comparison is ::text
-- rather than auth.uid().

-- create policy "message_reads: read own"
--   on public.message_reads
--   for select
--   to authenticated
--   using (user_id::text = auth.jwt() ->> 'sub');

-- create policy "message_reads: write own"
--   on public.message_reads
--   for insert
--   to authenticated
--   with check (user_id::text = auth.jwt() ->> 'sub');

-- create policy "message_reads: update own"
--   on public.message_reads
--   for update
--   to authenticated
--   using      (user_id::text = auth.jwt() ->> 'sub')
--   with check (user_id::text = auth.jwt() ->> 'sub');

-- A note on what these deliberately do NOT do. "Everyone in the
-- conversation may see the receipts" is the rule a group chat's ticks
-- actually need, and it is a join to the membership table -- which means
-- that table needs its own policy, or the join leaks what it was meant to
-- protect. Worth doing properly rather than guessing at, and the app does
-- not need it today because it does not read this table.


-- ---------------------------------------------------------------------------
-- 4. AFTER -- confirm
-- ---------------------------------------------------------------------------

select  c.relrowsecurity as rls_enabled,
        (select count(*) from pg_policies
          where schemaname = 'public' and tablename = 'message_reads')
          as policy_count
from    pg_class c
join    pg_namespace n on n.oid = c.relnamespace
where   n.nspname = 'public' and c.relname = 'message_reads';

-- And from outside, which is the only check that matters. With the
-- publishable key from SupabaseClasses.dart and no user token at all, this
-- should come back as [] rather than as rows:
--
--   curl -s "https://hekpfyxiduypovcvwffm.supabase.co/rest/v1/message_reads?select=*&limit=5" \
--        -H "apikey: sb_publishable_HSLwe3eiV6K_DCfgCwfSLw_YUM5HQ9F"
--
-- Run the same curl BEFORE section 2 as well. If it returns rows then, the
-- table has been readable by anyone who looked, and that is the fact that
-- decides whether anybody needs telling.


-- ---------------------------------------------------------------------------
-- 5. THE OTHER OPTION
-- ---------------------------------------------------------------------------
--
-- If 1(e) returns 0 and 1(d) shows nothing calls it, this table is a
-- leftover from building group chat and the honest fix is to drop it --
-- a table nobody uses cannot be secured wrong twice.
--
-- Check for dependents first; this is not reversible.
--
--   drop table public.message_reads;
