alter table public.analysis_runs
 add column technique_codes text[] not null default '{}'
 check(cardinality(technique_codes)<=3);

alter table public.feedback
 add column run_id uuid,
 add column suggestion_index integer,
 add column technique text,
 add constraint feedback_run_owner foreign key(user_id,run_id)
   references public.analysis_runs(user_id,request_id) on delete cascade,
 add constraint feedback_suggestion_shape check(
   (run_id is null and suggestion_index is null and technique is null)
   or
   (run_id is not null and suggestion_index between 0 and 2 and technique is not null and issues='{}'::text[])
 );

create unique index feedback_once_per_suggestion
 on public.feedback(user_id,run_id,suggestion_index)
 where run_id is not null;
