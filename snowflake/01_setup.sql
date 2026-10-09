-- =============================================================================
-- 01_setup.sql  â€”  one-time Snowflake setup for the ecom semantic layer project
-- Run as ACCOUNTADMIN (or SECURITYADMIN + SYSADMIN) in a Snowflake worksheet.
-- =============================================================================
use role accountadmin;

-- Compute ----------------------------------------------------------------------
create warehouse if not exists transforming
  warehouse_size = 'XSMALL'
  auto_suspend   = 60
  auto_resume    = true
  initially_suspended = true
  comment = 'dbt builds + MetricFlow metric queries';

-- Storage ----------------------------------------------------------------------
create database if not exists raw        comment = 'Landing zone (EL tools write here)';
create database if not exists analytics  comment = 'dbt-managed models';
create schema   if not exists raw.ecom;

-- Role used by dbt Core and MetricFlow ---------------------------------
create role if not exists transformer;
grant role transformer to role sysadmin;

grant usage   on warehouse transforming to role transformer;
grant usage   on database raw           to role transformer;
grant usage   on schema   raw.ecom      to role transformer;
grant create table on schema raw.ecom   to role transformer;   -- only so 02_generate_data.sql can run as this role;
                                                                -- in production an EL tool owns raw.*
grant select  on all tables    in schema raw.ecom to role transformer;
grant select  on future tables in schema raw.ecom to role transformer;
grant all     on database analytics     to role transformer;   -- dbt creates schemas here

-- Service user for dbt + MetricFlow (key-pair auth; Snowflake is phasing out
-- password-only sign-in). Generate a key pair locally first:
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
--   openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
-- Paste the body of rsa_key.pub (without the BEGIN/END lines) below.
create user if not exists dbt_svc
  type = service
  default_role = transformer
  default_warehouse = transforming
  comment = 'dbt Core + MetricFlow';
-- alter user dbt_svc set rsa_public_key = 'MIIBIjANBgkqh...';
grant role transformer to user dbt_svc;

-- Optional: let your own login use the role too
-- grant role transformer to user <your_user>;

