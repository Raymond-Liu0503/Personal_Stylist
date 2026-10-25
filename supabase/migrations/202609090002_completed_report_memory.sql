-- NULL distinguishes retakes/legacy runs from completed reports. A completed
-- report with no credible suggestions stores an empty array and still counts.
alter table public.analysis_runs
 alter column technique_codes drop not null,
 alter column technique_codes drop default;

update public.analysis_runs set technique_codes=null where technique_codes='{}'::text[];
