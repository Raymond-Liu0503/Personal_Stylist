-- Server-owned profile reservations. Keep the legacy signature for older deployments.
-- Operational selection lives in analysis_runs.versions, never signed report JSON.
create or replace function public.claim_analysis(p_user uuid,p_request uuid,p_versions jsonb,p_reserve bigint default 100000)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare d date:=(now() at time zone 'utc')::date;m date:=date_trunc('month',now() at time zone 'utc')::date;r public.analysis_runs;b public.budget_monthly;n integer;expected bigint;
begin
 if not (p_versions ? 'profile') then
  expected:=100000; -- Legacy server compatibility.
 elsif p_versions->>'profileVersion'='stylist-v1' then
  expected:=case p_versions->>'profile' when 'everyday-quick' then 100000 when 'everyday-deep' then 250000 when 'expert-quick' then 1200000 when 'expert-deep' then 5000000 else null end;
 elsif p_versions->>'profileVersion'='stylist-legacy-v1' and p_versions->>'profile'='everyday-quick' then
  expected:=100000;
 end if;
 if expected is null or p_reserve is null or p_reserve<>expected then raise exception 'Invalid reservation';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_user::text,0));
 select * into r from analysis_runs where user_id=p_user and request_id=p_request;
 if found then return case when r.state in ('reserved','dispatched') then 'DUPLICATE_ACTIVE' else 'DUPLICATE_FINISHED' end;end if;
 if not exists(select 1 from beta_access where user_id=p_user and enabled) then return 'BETA_REQUIRED';end if;
 if not coalesce((select accepted and policy_version='2026-09-01' from consents where user_id=p_user order by created_at desc,id desc limit 1),false) then return 'CONSENT_REQUIRED';end if;
 if exists(select 1 from analysis_runs where user_id=p_user and state in ('reserved','dispatched')) then return 'ANALYSIS_ACTIVE';end if;
 insert into usage_daily(user_id,day) values(p_user,d) on conflict do nothing;
 select dispatched_count into n from usage_daily where user_id=p_user and day=d for update;
 if n>=3 and not exists(select 1 from beta_access where user_id=p_user and daily_quota_exempt) then return 'QUOTA_EXHAUSTED';end if;
 insert into budget_monthly(month) values(m) on conflict do nothing;
 select * into b from budget_monthly where month=m for update;
 if b.reserved_microdollars+b.settled_microdollars+p_reserve>b.ceiling_microdollars then return 'BUDGET_EXHAUSTED';end if;
 update budget_monthly set reserved_microdollars=reserved_microdollars+p_reserve where month=m;
 insert into analysis_runs(request_id,user_id,state,versions,reserved_microdollars,budget_month,usage_date) values(p_request,p_user,'reserved',p_versions,p_reserve,m,d);
 return 'OK';
end $$;
revoke all on function public.claim_analysis(uuid,uuid,jsonb,bigint) from public,anon,authenticated;
grant execute on function public.claim_analysis(uuid,uuid,jsonb,bigint) to service_role;
