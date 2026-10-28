-- ---------------------------------------------------------------------------
-- A picture on a group chat
-- ---------------------------------------------------------------------------
--
-- One column, and one change to a function this file cannot see.
--
-- The column holds a finished Cloudflare delivery URL, not an image id.
-- Everywhere else in the app stores the bare id and builds the URL in PHP
-- with get_cloudflare_media_url -- but conversations live here, and
-- Postgres has no way to call that. The trade is that the variant is
-- fixed at upload time: moving group avatars to a larger one later means
-- rewriting these rows rather than changing one constant.
--
-- ---------------------------------------------------------------------------
-- 1. BEFORE -- the part that is easy to miss
-- ---------------------------------------------------------------------------
--
-- The inbox does not read `conversations` directly. It calls get_inbox,
-- and that function returns a fixed set of columns -- conv_id,
-- participant_ids, updated_at, is_group, group_name, and the last
-- message. Adding a column to the table does NOT add it to the function's
-- result, so the rows will keep arriving without it and every group will
-- keep drawing its initial.
--
-- Print the function and see for yourself. The new column has to be added
-- in three places in it: the RETURNS TABLE list, the SELECT, and any
-- GROUP BY the select has.
select pg_get_functiondef(p.oid)
from   pg_proc p
join   pg_namespace n on n.oid = p.pronamespace
where  n.nspname = 'public' and p.proname = 'get_inbox';

-- Group Info reads the table directly, so IT will see the new column the
-- moment section 2 runs. That asymmetry is worth knowing: setting a group
-- photo will appear to work, and show up nowhere in the list, until
-- get_inbox is updated too.

-- And the policies, because section 3 adds to them.
select  policyname, cmd, qual, with_check
from    pg_policies
where   schemaname = 'public' and tablename = 'conversations'
order by policyname;


-- ---------------------------------------------------------------------------
-- 2. THE CHANGE
-- ---------------------------------------------------------------------------

alter table public.conversations
  add column if not exists group_image text;

comment on column public.conversations.group_image is
  'Cloudflare Images delivery URL for a group chat avatar. A finished '
  'URL rather than an image id: Postgres cannot call '
  'get_cloudflare_media_url. Written by CloudflareImages.uploadAndGetUrl '
  'in the app. Null for one-to-one conversations.';


-- ---------------------------------------------------------------------------
-- 3. WHO MAY SET IT
-- ---------------------------------------------------------------------------
--
-- Anyone in the group. Not just whoever created it: a group photo is
-- shared property, the app has no admin concept for conversations, and
-- inventing one here would mean the only person who could ever fix a bad
-- photo is the person who made the group.
--
-- Written for participant_ids as text[]. If it is jsonb, this wants
--   participant_ids ? (auth.jwt() ->> 'sub')
-- instead.
--
-- Drop first so this file can be run twice.
drop policy if exists "conversations: members may set the group image"
  on public.conversations;

create policy "conversations: members may set the group image"
  on public.conversations
  for update
  to authenticated
  using (
    is_group = true
    and auth.jwt() ->> 'sub' = any(participant_ids)
  )
  with check (
    is_group = true
    and auth.jwt() ->> 'sub' = any(participant_ids)
  );

-- NOTE: an UPDATE policy covers the whole row, not one column. This lets
-- a member rewrite group_name and participant_ids as well, which they can
-- already do through Group Info, so it grants nothing new -- but it is
-- not the column-level grant the policy name suggests. If conversations
-- ever grows a field members should not touch, this policy is where that
-- goes wrong, and the fix is a trigger that rejects changes to it.


-- ---------------------------------------------------------------------------
-- 4. AFTER
-- ---------------------------------------------------------------------------

select column_name, data_type
from   information_schema.columns
where  table_schema = 'public'
and    table_name = 'conversations'
and    column_name = 'group_image';

-- And the one that actually matters, once get_inbox has been updated:
-- this should list group_image among its columns.
--
--   select * from get_inbox('<your user id>') limit 1;
