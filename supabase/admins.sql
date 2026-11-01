-- Admins can delete anyone's rep (and its clip). Add or remove admins only here, never from the app:
--   insert into public.admins (user_id) select id from public.profiles where lower(username) = 'name';
--   delete from public.admins where user_id = (select id from public.profiles where lower(username) = 'name');
create table if not exists public.admins (user_id uuid primary key references auth.users(id) on delete cascade, added_at timestamptz not null default now());
alter table public.admins enable row level security;
drop policy if exists "see if you are an admin" on public.admins;
create policy "see if you are an admin" on public.admins for select to authenticated using (user_id = (select auth.uid()));
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = (select auth.uid()));
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;
drop policy if exists "admins delete any" on public.docs;
create policy "admins delete any" on public.docs for delete to authenticated using ((select public.is_admin()));
drop policy if exists "members delete their own clips" on storage.objects;
create policy "members delete their own clips" on storage.objects for delete to authenticated using (bucket_id = 'clips' and owner_id = (select auth.uid())::text);
drop policy if exists "admins delete any clip" on storage.objects;
create policy "admins delete any clip" on storage.objects for delete to authenticated using (bucket_id = 'clips' and (select public.is_admin()));
insert into public.admins (user_id) select id from public.profiles where lower(username) = 'abfoandgo' on conflict do nothing;
