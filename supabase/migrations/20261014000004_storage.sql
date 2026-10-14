-- Receipt photos. Trello card 1.8.
--
-- Private bucket `receipts`. Object path: {group_id}/{uuid}.{ext}, where
-- ext is jpg, jpeg, png or webp and both ids are lowercase uuids. The app
-- picks a fresh uuid, uploads, then passes the path to add_expense /
-- update_expense. public.receipt_group_id() (0003) is the single definition
-- of a valid path; it returns null for anything else, and every policy below
-- fails closed on null.
--
-- Size and type limits are enforced by the Storage API from the bucket row,
-- before the object is written.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880,  -- 5 MiB
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- storage.objects already has RLS enabled by Supabase. Policy names are
-- shared by every bucket on that table, hence the "receipts:" prefix.

-- Any member of the group can view the group's receipts.
create policy "receipts: members read" on storage.objects
  for select to authenticated
  using (bucket_id = 'receipts'
         and public.is_group_member(public.receipt_group_id(name)));

-- A member can upload into their own group's folder, valid path only.
-- The Storage API stamps owner_id with the uploader's user id; clients
-- cannot choose it.
create policy "receipts: members upload to own group" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts'
              and public.is_group_member(public.receipt_group_id(name)));

-- Only the uploader can replace or delete their object, and a replacement
-- must stay inside a group they belong to.
create policy "receipts: uploader updates own" on storage.objects
  for update to authenticated
  using (bucket_id = 'receipts' and owner_id = (select auth.uid())::text)
  with check (bucket_id = 'receipts'
              and owner_id = (select auth.uid())::text
              and public.is_group_member(public.receipt_group_id(name)));

create policy "receipts: uploader deletes own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'receipts' and owner_id = (select auth.uid())::text);
