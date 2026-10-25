create table public.profiles (
 user_id uuid primary key references auth.users on delete cascade,
 preferences jsonb not null default '{}'::jsonb check(jsonb_typeof(preferences)='object'),
 deletion_stage text check(deletion_stage in ('revoked')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.consents (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users on delete cascade,
 policy_version text not null,accepted boolean not null,adult_confirmed boolean not null,
 created_at timestamptz not null default now(),check(not accepted or adult_confirmed)
);
create index consents_latest on public.consents(user_id,created_at desc);
create table public.beta_access(user_id uuid primary key references auth.users on delete cascade,enabled boolean not null default false);
create table public.saved_reports(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users on delete cascade,
 run_id uuid not null,schema_version integer not null check(schema_version=1),report jsonb not null,
 created_at timestamptz not null default now(),unique(user_id,run_id),check(octet_length(report::text)<30000)
);
create index reports_history on public.saved_reports(user_id,created_at desc,id desc);
create table public.analysis_runs(
 request_id uuid not null,user_id uuid not null references auth.users on delete cascade,
 state text not null check(state in ('reserved','dispatched','finished','failed','uncertain')),
 versions jsonb not null default '{}', input_tokens integer not null default 0,output_tokens integer not null default 0,
 reserved_microdollars bigint not null check(reserved_microdollars>=0),actual_microdollars bigint check(actual_microdollars>=0),
 budget_month date not null,usage_date date not null,dispatched_at timestamptz,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),primary key(user_id,request_id)
);
create unique index one_active_run on public.analysis_runs(user_id) where state in ('reserved','dispatched');
create table public.usage_daily(user_id uuid not null references auth.users on delete cascade,day date not null,dispatched_count integer not null default 0 check(dispatched_count between 0 and 3),primary key(user_id,day));
create table public.budget_monthly(month date primary key,ceiling_microdollars bigint not null default 20000000 check(ceiling_microdollars>=0),reserved_microdollars bigint not null default 0 check(reserved_microdollars>=0),settled_microdollars bigint not null default 0 check(settled_microdollars>=0));
create table public.feedback(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users on delete cascade,saved_report_id uuid references public.saved_reports on delete set null,helpful boolean not null,issues text[] not null default '{}',created_at timestamptz not null default now());

-- Ordinary clients can read owned data. All mutations are API-validated and server controlled.
do $$ declare t text; begin
 foreach t in array array['profiles','consents','beta_access','saved_reports','analysis_runs','usage_daily','budget_monthly','feedback'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 if t<>'budget_monthly' then
 execute format('grant select on public.%I to authenticated',t);
 execute format('create policy owned_read on public.%I for select to authenticated using (user_id = (select auth.uid()))',t);
 end if;
 end loop;
end $$;

create function public.claim_analysis(p_user uuid,p_request uuid,p_versions jsonb,p_reserve bigint default 100000)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare d date:=(now() at time zone 'utc')::date;m date:=date_trunc('month',now() at time zone 'utc')::date;r public.analysis_runs;b public.budget_monthly;n integer;
begin
 if p_reserve<>100000 then raise exception 'Invalid reservation';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_user::text,0));
 select * into r from analysis_runs where user_id=p_user and request_id=p_request;
 if found then return case when r.state in ('reserved','dispatched') then 'DUPLICATE_ACTIVE' else 'DUPLICATE_FINISHED' end;end if;
 if not exists(select 1 from beta_access where user_id=p_user and enabled) then return 'BETA_REQUIRED';end if;
 if not coalesce((select accepted and policy_version='2026-09-01' from consents where user_id=p_user order by created_at desc,id desc limit 1),false) then return 'CONSENT_REQUIRED';end if;
 if exists(select 1 from analysis_runs where user_id=p_user and state in ('reserved','dispatched')) then return 'ANALYSIS_ACTIVE';end if;
 insert into usage_daily(user_id,day) values(p_user,d) on conflict do nothing;
 select dispatched_count into n from usage_daily where user_id=p_user and day=d for update;
 if n>=3 then return 'QUOTA_EXHAUSTED';end if;
 insert into budget_monthly(month) values(m) on conflict do nothing;
 select * into b from budget_monthly where month=m for update;
 if b.reserved_microdollars+b.settled_microdollars+p_reserve>b.ceiling_microdollars then return 'BUDGET_EXHAUSTED';end if;
 update budget_monthly set reserved_microdollars=reserved_microdollars+p_reserve where month=m;
 insert into analysis_runs(request_id,user_id,state,versions,reserved_microdollars,budget_month,usage_date) values(p_request,p_user,'reserved',p_versions,p_reserve,m,d);
 return 'OK';
end $$;

create function public.dispatch_analysis(p_user uuid,p_request uuid) returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.analysis_runs;begin
 perform pg_advisory_xact_lock(hashtextextended(p_user::text,0));
 select * into r from analysis_runs where user_id=p_user and request_id=p_request for update;
 if not found or r.state<>'reserved' then return false;end if;
 if r.created_at<now()-interval '45 seconds' then return false;end if;
 if not coalesce((select accepted and policy_version='2026-09-01' from consents where user_id=p_user order by created_at desc,id desc limit 1),false) then return false;end if;
 update usage_daily set dispatched_count=dispatched_count+1 where user_id=p_user and day=r.usage_date and dispatched_count<3;
 if not found then return false;end if;
 update analysis_runs set state='dispatched',dispatched_at=now(),updated_at=now() where user_id=p_user and request_id=p_request;return true;
end $$;

create function public.settle_analysis(p_user uuid,p_request uuid,p_actual bigint,p_failed boolean default false,p_input integer default 0,p_output integer default 0)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.analysis_runs;begin
 if p_actual<0 or p_input<0 or p_output<0 then raise exception 'Invalid accounting';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_user::text,0));
 select * into r from analysis_runs where user_id=p_user and request_id=p_request for update;
 if not found or r.state in ('finished','failed') then return;end if;
 if p_actual is null and r.dispatched_at is not null then
 update analysis_runs set state='uncertain',updated_at=now(),input_tokens=p_input,output_tokens=p_output where user_id=p_user and request_id=p_request;return;
 end if;
 update budget_monthly set reserved_microdollars=reserved_microdollars-r.reserved_microdollars,settled_microdollars=settled_microdollars+coalesce(p_actual,0) where month=r.budget_month;
 update analysis_runs set state=case when p_failed then 'failed' else 'finished' end,actual_microdollars=coalesce(p_actual,0),input_tokens=p_input,output_tokens=p_output,updated_at=now() where user_id=p_user and request_id=p_request;
end $$;

create function public.maintain_analysis() returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.analysis_runs;begin
 for r in select * from analysis_runs where state in ('reserved','dispatched') and updated_at<now()-interval '2 minutes' loop
 perform settle_analysis(r.user_id,r.request_id,case when r.dispatched_at is null then 0 else null end,true);
 end loop;
 -- At 30 days conservatively charge unresolved reservations before removing user-linked operations.
 for r in select * from analysis_runs where state='uncertain' and created_at<now()-interval '30 days' loop
 perform settle_analysis(r.user_id,r.request_id,r.reserved_microdollars,true);
 end loop;
 delete from analysis_runs where state in ('finished','failed') and created_at<now()-interval '30 days';
 delete from feedback where created_at<now()-interval '30 days';
 delete from usage_daily where day<(now() at time zone 'utc')::date-30;
end $$;

-- Deleting a user conservatively settles any reservations before cascade removes run rows.
create function public.before_user_delete() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.analysis_runs;begin
 for r in select * from analysis_runs where user_id=old.id and state in ('reserved','dispatched','uncertain') loop
 perform settle_analysis(r.user_id,r.request_id,case when r.dispatched_at is null then 0 else r.reserved_microdollars end,true);
 end loop;return old;
end $$;
create trigger settle_deleted_user before delete on auth.users for each row execute function public.before_user_delete();

do $$ declare f regprocedure;begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('claim_analysis','dispatch_analysis','settle_analysis','maintain_analysis','before_user_delete') loop
 execute format('revoke all on function %s from public,anon,authenticated',f);execute format('grant execute on function %s to service_role',f);
 end loop;
end $$;
