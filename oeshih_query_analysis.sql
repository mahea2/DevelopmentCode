-- Analysis of the OESHIH query issues and solutions

-- Original query with issues:
/*
SELECT * 
FROM SFLDAT.OESHIH
WHERE 
    :input IS NULL
    OR shiuniq = :input
    OR shinumber = :input
    OR LOWER(bilname) LIKE LOWER('%' || :input || '%')
    OR customer = :input
    OR ponumber = :input
    OR lastinvnum = :input
*/

-- ISSUE 1: Logic Problem - Using OR instead of proper conditional logic
-- When :input IS NULL, it returns ALL records (which might be intended)
-- When :input has a value, it returns records matching ANY of the conditions
-- This means if you search for a customer, it will also return records where that value matches shiuniq, shinumber, etc.

-- ISSUE 2: Empty string handling
-- The query doesn't handle empty strings properly
-- When :input = '', it should be treated as NULL

-- ISSUE 3: Performance issue with LOWER() on both sides
-- Using LOWER() on both sides of LIKE is redundant

-- ISSUE 4: Data type mismatches
-- Different columns might have different data types
-- Comparing string input with numeric fields might cause issues

-- CORRECTED VERSION 1: Proper conditional logic with empty string handling
SELECT * 
FROM SFLDAT.OESHIH
WHERE 
    (:input IS NULL OR :input = '')
    OR shiuniq = :input
    OR shinumber = :input
    OR bilname LIKE '%' || :input || '%'
    OR customer = :input
    OR ponumber = :input
    OR lastinvnum = :input

-- CORRECTED VERSION 2: Case-insensitive search for bilname
SELECT * 
FROM SFLDAT.OESHIH
WHERE 
    (:input IS NULL OR :input = '')
    OR shiuniq = :input
    OR shinumber = :input
    OR UPPER(bilname) LIKE UPPER('%' || :input || '%')
    OR customer = :input
    OR ponumber = :input
    OR lastinvnum = :input

-- CORRECTED VERSION 3: Handle potential data type issues
SELECT * 
FROM SFLDAT.OESHIH
WHERE 
    (:input IS NULL OR :input = '')
    OR TO_CHAR(shiuniq) = :input
    OR TO_CHAR(shinumber) = :input
    OR UPPER(bilname) LIKE UPPER('%' || :input || '%')
    OR customer = :input
    OR ponumber = :input
    OR TO_CHAR(lastinvnum) = :input

-- ALTERNATIVE: Using REGEXP_LIKE for more flexible search
SELECT * 
FROM SFLDAT.OESHIH
WHERE 
    (:input IS NULL OR :input = '')
    OR TO_CHAR(shiuniq) = :input
    OR TO_CHAR(shinumber) = :input
    OR REGEXP_LIKE(bilname, :input, 'i')
    OR customer = :input
    OR ponumber = :input
    OR TO_CHAR(lastinvnum) = :input

-- RECOMMENDED VERSION: Most robust and performant
SELECT * 
FROM SFLDAT.OESHIH
WHERE 
    (:input IS NULL OR :input = '')
    OR shiuniq = :input
    OR shinumber = :input
    OR UPPER(bilname) LIKE UPPER('%' || :input || '%')
    OR customer = :input
    OR ponumber = :input
    OR lastinvnum = :input

-- For ORDS API, use this in your handler:
/*
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeshih',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_collection_feed,
        p_source         => 'SELECT * FROM SFLDAT.OESHIH WHERE (:input IS NULL OR :input = '''' OR shiuniq = :input OR shinumber = :input OR UPPER(bilname) LIKE UPPER(''%'' || :input || ''%'') OR customer = :input OR ponumber = :input OR lastinvnum = :input)',
        p_items_per_page => 25
    );
    COMMIT;
END;
/
*/

-- Test cases to verify the logic:
-- 1. :input = NULL or '' -> Returns all records
-- 2. :input = 'CUST123' -> Returns records where customer = 'CUST123'
-- 3. :input = 'SHIP001' -> Returns records where shinumber = 'SHIP001'
-- 4. :input = 'John' -> Returns records where bilname contains 'John' (case-insensitive)