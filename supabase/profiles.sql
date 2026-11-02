-- Profiles: each player chooses public or private, and can add a team, school, grad class and photo.
alter table public.profiles
  add column if not exists is_public boolean not null default false,
  add column if not exists team text, add column if not exists school text,
  add column if not exists grad_year int, add column if not exists avatar text, add column if not exists updated_at timestamptz;
alter table public.profiles
  add constraint profiles_team_len check (team is null or char_length(team) <= 40),
  add constraint profiles_school_len check (school is null or char_length(school) <= 60),
  add constraint profiles_grad_year_range check (grad_year is null or grad_year between 2000 and 2100),
  add constraint profiles_avatar_path check (avatar is null or avatar ~ '^[0-9a-f-]{36}/[A-Za-z0-9_-]{8,64}\.(jpg|png|webp)$');
drop policy if exists "anyone can see usernames" on public.profiles;
create policy "public profiles and your own" on public.profiles for select to anon, authenticated using (is_public or id = (select auth.uid()));
revoke insert, update, delete, truncate on public.profiles from anon, authenticated;
grant update (is_public, team, school, grad_year, avatar, updated_at) on public.profiles to authenticated;
create policy "edit your own profile" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('avatars', 'avatars', true, 2097152, array['image/jpeg','image/png','image/webp']) on conflict (id) do nothing;
create policy "upload your own photo" on storage.objects for insert to authenticated with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "delete your own photo" on storage.objects for delete to authenticated using (bucket_id = 'avatars' and owner_id = (select auth.uid())::text);
