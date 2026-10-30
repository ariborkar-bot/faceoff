-- FO & GO accounts: sign up with email, username and password to post reps, like and flag.
-- Everyone can still watch the board. Old reps posted before accounts stay up, and can be claimed by
-- whoever posted them (the device that posted them proves it with its secret).

-- usernames
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (username ~ '^[A-Za-z0-9_.]{3,20}$'),
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_lower on public.profiles (lower(username));
alter table public.profiles enable row level security;
grant select on public.profiles to anon, authenticated;
drop policy if exists "anyone can see usernames" on public.profiles;
create policy "anyone can see usernames" on public.profiles for select to anon, authenticated using (true);

-- the profile is made at sign-up from the username given (sign-up fails if it's taken)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username) values (new.id, new.raw_user_meta_data->>'username');
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- is a username free? (for a friendly message before signing up)
create or replace function public.username_free(p_username text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where lower(username) = lower(p_username));
$$;
grant execute on function public.username_free(text) to anon, authenticated;

-- posts now belong to an account
alter table public.docs add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.docs alter column owner_hash drop not null;
alter table public.docs drop constraint if exists docs_owner_hash_check;
alter table public.docs add constraint docs_owner_hash_check check (owner_hash is null or owner_hash ~ '^[0-9a-f]{64}$');
create index if not exists docs_user_id on public.docs (user_id);

drop policy if exists "anyone can add" on public.docs;
drop policy if exists "members can add" on public.docs;
create policy "members can add" on public.docs for insert to authenticated with check (
  user_id = auth.uid() and data->>'uid' = auth.uid()::text and pg_column_size(data) < 4000 and (
    collection <> 'attempts' or (
      (data->>'timeMs') ~ '^[0-9]+$' and (data->>'timeMs')::int between 120 and 15000
      and data->>'handle' = (select username from public.profiles where id = auth.uid())
      and char_length(coalesce(data->>'club', '')) <= 30
      and coalesce(data->>'asset', '') ~ '^[A-Za-z0-9_-]{8,64}\.(mp4|webm)$'
    )
  )
);
grant delete on public.docs to authenticated;
drop policy if exists "members delete their own" on public.docs;
create policy "members delete their own" on public.docs for delete to authenticated using (user_id = auth.uid());

-- claim reps this device posted before accounts existed
create or replace function public.claim_docs(p_secret text) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer; uname text;
begin
  if auth.uid() is null then return 0; end if;
  select username into uname from public.profiles where id = auth.uid();
  update public.docs set user_id = auth.uid(),
         data = jsonb_set(case when collection = 'attempts' and uname is not null then jsonb_set(data, '{handle}', to_jsonb(uname)) else data end, '{uid}', to_jsonb(auth.uid()::text))
   where owner_hash = encode(sha256(convert_to(p_secret, 'UTF8')), 'hex') and user_id is null;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.claim_docs(text) from public;
grant execute on function public.claim_docs(text) to authenticated;

-- clips: only members can upload
drop policy if exists "anyone can upload clips" on storage.objects;
drop policy if exists "members can upload clips" on storage.objects;
create policy "members can upload clips" on storage.objects for insert to authenticated with check (bucket_id = 'clips');
