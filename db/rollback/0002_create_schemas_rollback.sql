-- =====================================================================
-- Rollback: 0002_create_schemas_rollback
-- Project: ApexCore
-- Database: PostgreSQL
-- Purpose: Drop base schemas created for ApexCore
-- =====================================================================

DROP SCHEMA IF EXISTS reporting CASCADE;
DROP SCHEMA IF EXISTS finance CASCADE;
DROP SCHEMA IF EXISTS inventory CASCADE;
DROP SCHEMA IF EXISTS core CASCADE;
