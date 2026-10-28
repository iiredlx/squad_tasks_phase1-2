-- Squad Tasks — المرحلة 1: الجداول والعلاقات وسياسات الأمان (RLS)
-- شغّل هذا الملف كاملًا مرة واحدة في Supabase > SQL Editor.

create extension if not exists pgcrypto;

-- ============ الأنواع ============
create type public.user_role as enum ('admin', 'player');
create type public.target_type as enum ('single', 'all', 'selected');
create type public.assignment_status as enum
  ('new', 'in_progress', 'pending_review', 'completed', 'rejected', 'late', 'cancelled');
create type public.evidence_status as enum ('pending', 'approved', 'rejected');

-- ============ الجداول ============
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 2 and 40),
  avatar_path text,
  role public.user_role not null default 'player',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
-- أدمن واحد فقط
create unique index profiles_single_admin on public.profiles (role) where role = 'admin';

create table public.player_access_codes (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles(id) on delete cascade,
  code_hash text not null unique,            -- HMAC للكود، لا يُخزَّن الكود نفسه
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  last_used_at timestamptz
);
-- كود فعّال واحد فقط لكل لاعب
create unique index one_active_code_per_player
  on public.player_access_codes (player_id) where revoked_at is null;

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 2 and 120),
  description text not null default '' check (char_length(description) <= 4000),
  image_path text,
  created_by uuid not null references public.profiles(id),
  target_type public.target_type not null,
  created_at timestamptz not null default now(),
  is_active boolean not null default true
);

create table public.task_assignments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  player_id uuid not null references public.profiles(id),
  assigned_at timestamptz not null default now(),
  due_at timestamptz not null default (now() + interval '12 hours'),
  status public.assignment_status not null default 'new',
  completed_at timestamptz,
  constraint due_after_assigned check (due_at > assigned_at),
  constraint completed_has_time check (status <> 'completed' or completed_at is not null)
);
-- منع الإسناد المكرر (يُسمح بإسناد جديد بعد إلغاء القديم)
create unique index one_live_assignment_per_player_task
  on public.task_assignments (task_id, player_id) where status <> 'cancelled';
create index idx_assignments_player on public.task_assignments (player_id, status);
create index idx_assignments_due on public.task_assignments (due_at);

create table public.task_evidence (
  id uuid primary key default gen_random_uuid(),
  task_assignment_id uuid not null references public.task_assignments(id) on delete restrict,
  player_id uuid not null references public.profiles(id),
  submitted_at timestamptz not null default now(),
  status public.evidence_status not null default 'pending',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text check (rejection_reason is null or char_length(rejection_reason) <= 500),
  constraint review_consistency check (
    (status = 'pending' and reviewed_at is null and reviewed_by is null) or
    (status in ('approved', 'rejected') and reviewed_at is not null and reviewed_by is not null)
  )
);
create index idx_evidence_assignment on public.task_evidence (task_assignment_id);

create table public.evidence_files (
  id uuid primary key default gen_random_uuid(),
  evidence_id uuid not null references public.task_evidence(id) on delete restrict,
  storage_path text not null unique,
  created_at timestamptz not null default now()
);

create table public.notification_logs (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles(id),
  task_assignment_id uuid not null references public.task_assignments(id),
  notification_type text not null,           -- مثل reminder_10h_left
  scheduled_at timestamptz not null,
  sent_at timestamptz,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'sent', 'failed', 'skipped')),
  attempts int not null default 0,
  last_error text,
  unique (task_assignment_id, notification_type)
);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null default 'android',
  created_at timestamptz not null default now()
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  target_kind text,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.login_attempts (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('admin', 'player')),
  identifier text not null,
  success boolean not null,
  created_at timestamptz not null default now()
);
create index idx_login_attempts on public.login_attempts (kind, identifier, created_at desc);

-- ============ دوال الصلاحيات ============
-- الجلسة ما زالت حيّة؟ (تُحذف الجلسة عند إلغاء الكود فيتوقف الوصول فورًا)
create or replace function public.has_live_session()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.sessions s
    where s.id = nullif(auth.jwt() ->> 'session_id', '')::uuid
  );
$$;

create or replace function public.is_active_member()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_live_session()
     and exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_active);
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.has_live_session()
     and exists (
       select 1 from public.profiles p
       where p.id = auth.uid() and p.is_active and p.role = 'admin'
     );
$$;

revoke all on function public.has_live_session() from public, anon;
revoke all on function public.is_active_member() from public, anon;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.has_live_session() to authenticated;
grant execute on function public.is_active_member() to authenticated;
grant execute on function public.is_admin() to authenticated;

-- إنهاء كل جلسات لاعب (تستدعيها Edge Function فقط)
create or replace function public.revoke_player_sessions(p_player_id uuid)
returns void language sql security definer set search_path = '' as $$
  delete from auth.sessions where user_id = p_player_id;
$$;
revoke all on function public.revoke_player_sessions(uuid) from public, anon, authenticated;
grant execute on function public.revoke_player_sessions(uuid) to service_role;

-- قائمة اللاعبين للأدمن (تعرض حالة الكود دون كشفه)
create or replace function public.admin_list_players()
returns table (
  id uuid, display_name text, avatar_path text, is_active boolean,
  created_at timestamptz, has_active_code boolean, last_used_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select p.id, p.display_name, p.avatar_path, p.is_active, p.created_at,
    exists (
      select 1 from public.player_access_codes c
      where c.player_id = p.id and c.revoked_at is null
        and (c.expires_at is null or c.expires_at > now())
    ),
    (select max(c.last_used_at) from public.player_access_codes c where c.player_id = p.id)
  from public.profiles p
  where p.role = 'player' and public.is_admin()
  order by p.created_at;
$$;
revoke all on function public.admin_list_players() from public, anon;
grant execute on function public.admin_list_players() to authenticated;

-- ============ Triggers للحماية ============
-- منع تغيير الدور أو المعرّف من أي مستخدم عادي
create or replace function public.protect_profile()
returns trigger language plpgsql set search_path = '' as $$
begin
  if auth.role() = 'authenticated' then
    if new.role is distinct from old.role
       or new.id is distinct from old.id
       or new.created_at is distinct from old.created_at then
      raise exception 'protected columns cannot be changed';
    end if;
  end if;
  return new;
end $$;
create trigger trg_protect_profile before update on public.profiles
  for each row execute function public.protect_profile();

-- موعد الانتهاء = وقت الإسناد + 12 ساعة دائمًا
create or replace function public.set_assignment_due()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.due_at := new.assigned_at + interval '12 hours';
  return new;
end $$;
create trigger trg_assignment_due before insert on public.task_assignments
  for each row execute function public.set_assignment_due();

-- الإثبات بعد إرساله: لا يتغير وقته أو إسناده أو صاحبه
create or replace function public.protect_evidence()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.submitted_at is distinct from old.submitted_at
     or new.task_assignment_id is distinct from old.task_assignment_id
     or new.player_id is distinct from old.player_id then
    raise exception 'evidence identity and submit time are immutable';
  end if;
  return new;
end $$;
create trigger trg_protect_evidence before update on public.task_evidence
  for each row execute function public.protect_evidence();

-- ============ RLS ============
alter table public.profiles            enable row level security;
alter table public.player_access_codes enable row level security;
alter table public.tasks               enable row level security;
alter table public.task_assignments    enable row level security;
alter table public.task_evidence       enable row level security;
alter table public.evidence_files      enable row level security;
alter table public.notification_logs   enable row level security;
alter table public.device_tokens       enable row level security;
alter table public.audit_log           enable row level security;
alter table public.login_attempts      enable row level security;

-- profiles: الجميع (الأعضاء الفعّالون) يشاهدون، الأدمن فقط يعدّل
create policy profiles_select on public.profiles
  for select to authenticated using (public.is_active_member());
create policy profiles_admin_update on public.profiles
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- tasks / assignments / evidence / files: مشاهدة للأعضاء، كتابة للأدمن
create policy tasks_select on public.tasks
  for select to authenticated using (public.is_active_member());
create policy tasks_admin_insert on public.tasks
  for insert to authenticated with check (public.is_admin() and created_by = auth.uid());
create policy tasks_admin_update on public.tasks
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy assignments_select on public.task_assignments
  for select to authenticated using (public.is_active_member());
create policy assignments_admin_insert on public.task_assignments
  for insert to authenticated with check (public.is_admin());
create policy assignments_admin_update on public.task_assignments
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy evidence_select on public.task_evidence
  for select to authenticated using (public.is_active_member());
create policy evidence_admin_update on public.task_evidence
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy evidence_files_select on public.evidence_files
  for select to authenticated using (public.is_active_member());

-- الإشعارات: اللاعب يرى سجلاته، والأدمن يرى الكل
create policy notif_select on public.notification_logs
  for select to authenticated
  using (public.is_active_member() and (player_id = auth.uid() or public.is_admin()));

-- توكنات الأجهزة: كل لاعب يدير توكناته فقط
create policy device_tokens_select on public.device_tokens
  for select to authenticated using (public.is_active_member() and player_id = auth.uid());
create policy device_tokens_insert on public.device_tokens
  for insert to authenticated with check (public.is_active_member() and player_id = auth.uid());
create policy device_tokens_delete on public.device_tokens
  for delete to authenticated using (public.is_active_member() and player_id = auth.uid());

-- سجل التدقيق: للأدمن فقط
create policy audit_admin_select on public.audit_log
  for select to authenticated using (public.is_admin());

-- player_access_codes و login_attempts: لا سياسات = لا وصول من التطبيق إطلاقًا
revoke all on public.player_access_codes from anon, authenticated;
revoke all on public.login_attempts from anon, authenticated;
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;

-- ============ التخزين (Storage) — كل الحاويات خاصة ============
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',     'avatars',     false, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('task-images', 'task-images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('evidence',    'evidence',    false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy storage_avatars_read on storage.objects
  for select to authenticated using (bucket_id = 'avatars' and public.is_active_member());
create policy storage_avatars_admin_write on storage.objects
  for insert to authenticated with check (bucket_id = 'avatars' and public.is_admin());
create policy storage_avatars_admin_update on storage.objects
  for update to authenticated using (bucket_id = 'avatars' and public.is_admin());
create policy storage_avatars_admin_delete on storage.objects
  for delete to authenticated using (bucket_id = 'avatars' and public.is_admin());

create policy storage_taskimg_read on storage.objects
  for select to authenticated using (bucket_id = 'task-images' and public.is_active_member());
create policy storage_taskimg_admin_write on storage.objects
  for insert to authenticated with check (bucket_id = 'task-images' and public.is_admin());
create policy storage_taskimg_admin_delete on storage.objects
  for delete to authenticated using (bucket_id = 'task-images' and public.is_admin());

-- صور الإثبات: الجميع يشاهد، واللاعب يرفع داخل مجلد باسم معرّفه فقط
create policy storage_evidence_read on storage.objects
  for select to authenticated using (bucket_id = 'evidence' and public.is_active_member());
create policy storage_evidence_player_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'evidence' and public.is_active_member()
    and (storage.foldername(name))[1] = auth.uid()::text
  );
