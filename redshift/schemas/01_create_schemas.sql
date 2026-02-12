-- Create Database Schemas for Research Data Platform V2
-- This script creates the staging, integration, presentation, and control schemas

-- =====================================================
-- 1. STAGING SCHEMA
-- =====================================================
-- Temporary landing area for raw data from S3
-- Data is validated but not yet transformed

CREATE SCHEMA IF NOT EXISTS staging;

COMMENT ON SCHEMA staging IS 'Staging area for raw data from S3 before transformation';

-- =====================================================
-- 2. INTEGRATION SCHEMA
-- =====================================================
-- Business logic applied, temporal versioning, corporate actions
-- Historical vault tables with full audit trail

CREATE SCHEMA IF NOT EXISTS integration;

COMMENT ON SCHEMA integration IS 'Integration layer with business logic and temporal versioning';

-- =====================================================
-- 3. PRESENTATION SCHEMA
-- =====================================================
-- Optimized star schema for analyst queries
-- Fact and dimension tables with precomputed features

CREATE SCHEMA IF NOT EXISTS presentation;

COMMENT ON SCHEMA presentation IS 'Presentation layer with optimized star schema for analytics';

-- =====================================================
-- 4. CONTROL SCHEMA
-- =====================================================
-- ETL metadata, high-water marks, job tracking

CREATE SCHEMA IF NOT EXISTS control;

COMMENT ON SCHEMA control IS 'Control tables for ETL metadata and job tracking';

-- =====================================================
-- Grant Permissions
-- =====================================================

-- Grant usage on schemas to analyst role (to be created)
-- GRANT USAGE ON SCHEMA staging TO analyst_role;
-- GRANT USAGE ON SCHEMA integration TO analyst_role;
-- GRANT USAGE ON SCHEMA presentation TO analyst_role;
-- GRANT USAGE ON SCHEMA control TO analyst_role;

-- Grant select on presentation schema to analysts
-- GRANT SELECT ON ALL TABLES IN SCHEMA presentation TO analyst_role;

COMMIT;
