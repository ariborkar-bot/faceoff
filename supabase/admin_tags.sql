-- Lets the app show an "Admin" tag next to every admin's name. Admin ids are public; nothing else is exposed.
create or replace function public.admin_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select user_id from public.admins;
$$;
revoke all on function public.admin_ids() from public;
grant execute on function public.admin_ids() to anon, authenticated;
