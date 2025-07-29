-- Complete ORDS Setup for OEINVH API Endpoint
-- This script sets up the REST API endpoint with proper parameter handling

-- Step 1: Create the module if it doesn't exist
BEGIN
    ORDS.DEFINE_MODULE(
        p_module_name    => 'salesforceext',
        p_base_path      => 'salesforceext/',
        p_items_per_page => 25,
        p_status         => 'PUBLISHED',
        p_comments       => 'Salesforce External API Module'
    );
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        -- Module might already exist, continue
        NULL;
END;
/

-- Step 2: Create the template for the OEINVH endpoint
BEGIN
    ORDS.DEFINE_TEMPLATE(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeinvh',
        p_priority       => 0,
        p_etag_type      => 'HASH',
        p_etag_query     => NULL,
        p_comments       => 'OEINVH table endpoint with optional filtering'
    );
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        -- Template might already exist, continue
        NULL;
END;
/

-- Step 3: Define the GET handler with proper parameter handling
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeinvh',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_collection_feed,
        p_source         => 'SELECT * FROM SFLDAT.OEINVH WHERE (:invuniq IS NULL OR :invuniq = '''' OR invuniq = :invuniq) AND (:customer IS NULL OR :customer = '''' OR customer = :customer)',
        p_items_per_page => 25,
        p_comments       => 'Get OEINVH records with optional filtering by invuniq or customer'
    );
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        -- Handler might already exist, drop and recreate
        ORDS.DELETE_HANDLER(
            p_module_name => 'salesforceext',
            p_pattern     => 'sfldat/oeinvh',
            p_method      => 'GET'
        );
        
        ORDS.DEFINE_HANDLER(
            p_module_name    => 'salesforceext',
            p_pattern        => 'sfldat/oeinvh',
            p_method         => 'GET',
            p_source_type    => ORDS.source_type_collection_feed,
            p_source         => 'SELECT * FROM SFLDAT.OEINVH WHERE (:invuniq IS NULL OR :invuniq = '''' OR invuniq = :invuniq) AND (:customer IS NULL OR :customer = '''' OR customer = :customer)',
            p_items_per_page => 25,
            p_comments       => 'Get OEINVH records with optional filtering by invuniq or customer'
        );
        COMMIT;
END;
/

-- Step 4: Enable the module
BEGIN
    ORDS.ENABLE_OBJECT(
        p_enabled      => TRUE,
        p_schema       => 'SFLDAT',
        p_object       => 'OEINVH',
        p_object_type  => 'TABLE',
        p_object_alias => 'oeinvh'
    );
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        -- Object might already be enabled, continue
        NULL;
END;
/

-- Step 5: Grant necessary privileges (run as DBA or schema owner)
-- GRANT SELECT ON SFLDAT.OEINVH TO ORDS_PUBLIC_USER;

-- Verification queries
-- Check if the endpoint is properly configured
SELECT 
    m.module_name,
    t.pattern,
    h.method,
    h.source_type,
    h.source
FROM user_ords_modules m
JOIN user_ords_templates t ON m.module_id = t.module_id
JOIN user_ords_handlers h ON t.template_id = h.template_id
WHERE m.module_name = 'salesforceext'
  AND t.pattern = 'sfldat/oeinvh';

-- Test the endpoint URLs:
-- 1. Get all records: https://testitrack.servicefoods.co.nz/ords/salesforceext/sfldat/oeinvh
-- 2. Filter by invuniq: https://testitrack.servicefoods.co.nz/ords/salesforceext/sfldat/oeinvh?invuniq=YOUR_INVUNIQ_VALUE
-- 3. Filter by customer: https://testitrack.servicefoods.co.nz/ords/salesforceext/sfldat/oeinvh?customer=YOUR_CUSTOMER_VALUE
-- 4. Filter by both: https://testitrack.servicefoods.co.nz/ords/salesforceext/sfldat/oeinvh?invuniq=YOUR_INVUNIQ_VALUE&customer=YOUR_CUSTOMER_VALUE