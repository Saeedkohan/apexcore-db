-- =====================================================================
-- Migration: 0002_create_schemas
-- Project: ApexCore
-- Database: PostgreSQL
-- Purpose: Create base schemas for modular database organization
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS finance;
CREATE SCHEMA IF NOT EXISTS reporting;
