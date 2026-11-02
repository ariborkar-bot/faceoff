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

-- admin user list (read-only)
create or replace function public.admin_users()
returns table (id uuid, username text, email text, joined timestamptz, last_sign_in timestamptz, confirmed boolean, reps bigint, is_admin boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'admins only' using errcode = '42501'; end if;
  return query
    select u.id, p.username, u.email::text, u.created_at, u.last_sign_in_at, (u.email_confirmed_at is not null),
           (select count(*) from public.docs d where d.user_id = u.id and d.collection = 'attempts'),
           exists (select 1 from public.admins a where a.user_id = u.id)
    from auth.users u left join public.profiles p on p.id = u.id
    order by u.created_at desc;
end $$;
revoke all on function public.admin_users() from public, anon;
grant execute on function public.admin_users() to authenticated;
