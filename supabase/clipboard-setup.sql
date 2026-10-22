-- Clipboard templates: database setup
-- Run once in Supabase > SQL Editor (choose "with RLS" if asked). Safe to run again.
-- Each signed-in person has their own templates; nobody else can see or change them.

create table if not exists public.clip_templates (
  id           uuid primary key default gen_random_uuid(),
  owner        text not null default lower(auth.jwt() ->> 'email'),
  title        text not null check (length(trim(title)) > 0),
  body         text not null default '',
  category     text,
  pinned       boolean not null default false,
  use_count    int not null default 0,
  last_used_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists clip_templates_owner_idx on public.clip_templates (owner);

-- The owner is always the person signed in, and never changes
create or replace function public.clip_stamp() returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.owner := lower(auth.jwt() ->> 'email');
  else
    new.owner := old.owner;
    if (new.title, new.body, new.category, new.pinned) is distinct from (old.title, old.body, old.category, old.pinned) then
      new.updated_at := now();
    end if;
  end if;
  return new;
end $$;
drop trigger if exists clip_stamp on public.clip_templates;
create trigger clip_stamp before insert or update on public.clip_templates
  for each row execute function public.clip_stamp();

alter table public.clip_templates enable row level security;
drop policy if exists "own templates" on public.clip_templates;
create policy "own templates" on public.clip_templates for all to authenticated
  using (owner = lower(auth.jwt() ->> 'email'))
  with check (owner = lower(auth.jwt() ->> 'email'));

-- Count a copy (for "most used" ordering)
create or replace function public.clip_used(p_id uuid) returns void
  language sql security invoker set search_path = public as $$
  update public.clip_templates set use_count = use_count + 1, last_used_at = now() where id = p_id
$$;
grant execute on function public.clip_used(uuid) to authenticated;
