-- Sign in with a username: returns the account's email only when the password is right,
-- so usernames never reveal emails. 10 wrong tries per username in 15 minutes locks it for a while.
create table if not exists public.login_attempts (username text not null, at timestamptz not null default now());
create index if not exists login_attempts_u on public.login_attempts (username, at);
alter table public.login_attempts enable row level security;
create or replace function public.login_email(p_username text, p_password text)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare v_email text; v_hash text; v_user text := lower(trim(p_username));
begin
  delete from public.login_attempts where at < now() - interval '1 day';
  if (select count(*) from public.login_attempts where username = v_user and at > now() - interval '15 minutes') >= 10 then
    raise exception 'too many tries' using errcode = 'P0001';
  end if;
  select u.email::text, u.encrypted_password into v_email, v_hash
    from auth.users u join public.profiles p on p.id = u.id where lower(p.username) = v_user;
  if v_email is null or v_hash is null or v_hash = '' or extensions.crypt(p_password, v_hash) <> v_hash then
    insert into public.login_attempts (username) values (v_user);
    perform pg_sleep(0.4);
    return null;
  end if;
  return v_email;
end $$;
revoke all on function public.login_email(text, text) from public;
grant execute on function public.login_email(text, text) to anon, authenticated;
