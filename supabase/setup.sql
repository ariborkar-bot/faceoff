-- Face-Off Clock: shared leaderboard setup. Paste all of this into Supabase → SQL Editor → Run.

-- 1. One table holds every posted run, like and flag.
create table if not exists public.docs (
  collection text not null check (collection in ('attempts', 'likes', 'flags')),
  id text not null check (char_length(id) between 1 and 120),
  data jsonb not null,
  owner_hash text not null check (owner_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  primary key (collection, id)
);
alter table public.docs enable row level security;
grant select, insert on public.docs to anon, authenticated;

-- 2. Everyone can see the board.
drop policy if exists "anyone can read" on public.docs;
create policy "anyone can read" on public.docs for select to anon, authenticated using (true);

-- 3. Anyone can post, but only sensible runs (0.12 s – 15 s, a 2–20 character name).
drop policy if exists "anyone can add" on public.docs;
create policy "anyone can add" on public.docs for insert to anon, authenticated with check (
  data->>'uid' = owner_hash and pg_column_size(data) < 4000 and (
    collection <> 'attempts' or (
      (data->>'timeMs') ~ '^[0-9]+$' and (data->>'timeMs')::int between 120 and 15000
      and char_length(coalesce(data->>'handle', '')) between 2 and 20
      and char_length(coalesce(data->>'club', '')) <= 30
      and coalesce(data->>'asset', '') ~ '^[A-Za-z0-9_-]{8,64}\.(mp4|webm)$'
    )
  )
);

-- 4. Only the phone that posted something can delete it (it proves it with a secret only that phone knows).
create or replace function public.delete_doc(p_collection text, p_id text, p_secret text)
returns boolean language sql security definer set search_path = public as $$
  with d as (
    delete from public.docs
    where collection = p_collection and id = p_id
      and owner_hash = encode(sha256(convert_to(p_secret, 'UTF8')), 'hex')
    returning 1)
  select exists (select 1 from d);
$$;
revoke all on function public.delete_doc(text, text, text) from public;
grant execute on function public.delete_doc(text, text, text) to anon, authenticated;

-- 5. Video clips: anyone can watch, anyone can upload an mp4/webm up to 20 MB, nobody can overwrite or delete.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('clips', 'clips', true, 20971520, array['video/mp4', 'video/webm'])
on conflict (id) do update set public = true, file_size_limit = 20971520, allowed_mime_types = array['video/mp4', 'video/webm'];
drop policy if exists "anyone can upload clips" on storage.objects;
create policy "anyone can upload clips" on storage.objects for insert to anon, authenticated with check (bucket_id = 'clips');
