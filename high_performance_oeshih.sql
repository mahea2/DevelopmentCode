-- High Performance OESHIH query solutions
-- Avoid TO_CHAR() conversions that kill performance

-- PROBLEM: TO_CHAR() prevents index usage and causes full table scans
-- SOLUTION: Use separate endpoints or smart data type detection

-- SOLUTION 1: Separate endpoints for different data types (BEST PERFORMANCE)
-- Create different API endpoints based on what you're searching for

-- Endpoint 1: Search by numeric values (shiuniq, shinumber, lastinvnum)
SELECT * FROM SFLDAT.OESHIH 
WHERE shiuniq = :input 
   OR shinumber = :input 
   OR lastinvnum = :input

-- Endpoint 2: Search by string values (customer, ponumber, bilname)
SELECT * FROM SFLDAT.OESHIH 
WHERE customer = :input 
   OR ponumber = :input 
   OR UPPER(bilname) LIKE UPPER('%' || :input || '%')

-- SOLUTION 2: Smart input detection with CASE (GOOD PERFORMANCE)
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR (
       -- If input is numeric, search numeric fields only
       CASE 
           WHEN REGEXP_LIKE(:input, '^[0-9]+$') THEN
               shiuniq = TO_NUMBER(:input) 
               OR shinumber = TO_NUMBER(:input) 
               OR lastinvnum = TO_NUMBER(:input)
           ELSE 0
       END = 1
   )
   OR (
       -- If input is string, search string fields only
       customer = :input 
       OR ponumber = :input 
       OR UPPER(bilname) LIKE UPPER('%' || :input || '%')
   )

-- SOLUTION 3: Use UNION ALL for better performance
SELECT * FROM SFLDAT.OESHIH WHERE shiuniq = :input
UNION ALL
SELECT * FROM SFLDAT.OESHIH WHERE shinumber = :input AND shiuniq != :input
UNION ALL
SELECT * FROM SFLDAT.OESHIH WHERE lastinvnum = :input AND shiuniq != :input AND shinumber != :input
UNION ALL
SELECT * FROM SFLDAT.OESHIH WHERE customer = :input AND shiuniq != :input AND shinumber != :input AND lastinvnum != :input
UNION ALL
SELECT * FROM SFLDAT.OESHIH WHERE ponumber = :input AND shiuniq != :input AND shinumber != :input AND lastinvnum != :input AND customer != :input
UNION ALL
SELECT * FROM SFLDAT.OESHIH WHERE UPPER(bilname) LIKE UPPER('%' || :input || '%') 
    AND shiuniq != :input AND shinumber != :input AND lastinvnum != :input AND customer != :input AND ponumber != :input
WHERE (:input IS NOT NULL AND :input != '')

-- SOLUTION 4: Required indexes for maximum performance
-- Create these indexes first:
/*
CREATE INDEX idx_oeshih_shiuniq ON SFLDAT.OESHIH(shiuniq);
CREATE INDEX idx_oeshih_shinumber ON SFLDAT.OESHIH(shinumber);
CREATE INDEX idx_oeshih_lastinvnum ON SFLDAT.OESHIH(lastinvnum);
CREATE INDEX idx_oeshih_customer ON SFLDAT.OESHIH(customer);
CREATE INDEX idx_oeshih_ponumber ON SFLDAT.OESHIH(ponumber);
CREATE INDEX idx_oeshih_bilname_upper ON SFLDAT.OESHIH(UPPER(bilname));
*/

-- SOLUTION 5: Hybrid approach - Use different strategies based on input
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR (
       -- For numeric input, use direct numeric comparison
       CASE 
           WHEN REGEXP_LIKE(:input, '^[0-9]+$') THEN
               shiuniq = TO_NUMBER(:input) 
               OR shinumber = TO_NUMBER(:input) 
               OR lastinvnum = TO_NUMBER(:input)
           ELSE 0
       END = 1
   )
   OR (
       -- For string input, use string comparison
       customer = :input 
       OR ponumber = :input 
       OR UPPER(bilname) LIKE UPPER('%' || :input || '%')
   )

-- RECOMMENDED ORDS IMPLEMENTATION:

-- Option A: Single endpoint with smart detection
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeshih',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_collection_feed,
        p_source         => 'SELECT * FROM SFLDAT.OESHIH WHERE (:input IS NULL OR :input = '''') OR (CASE WHEN REGEXP_LIKE(:input, ''^[0-9]+$'') THEN shiuniq = TO_NUMBER(:input) OR shinumber = TO_NUMBER(:input) OR lastinvnum = TO_NUMBER(:input) ELSE 0 END = 1) OR (customer = :input OR ponumber = :input OR UPPER(bilname) LIKE UPPER(''%'' || :input || ''%''))',
        p_items_per_page => 25
    );
    COMMIT;
END;
/

-- Option B: Separate endpoints (BEST PERFORMANCE)
-- Endpoint 1: Numeric search
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeshih/numeric',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_collection_feed,
        p_source         => 'SELECT * FROM SFLDAT.OESHIH WHERE shiuniq = :input OR shinumber = :input OR lastinvnum = :input',
        p_items_per_page => 25
    );
    COMMIT;
END;
/

-- Endpoint 2: String search
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeshih/text',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_collection_feed,
        p_source         => 'SELECT * FROM SFLDAT.OESHIH WHERE customer = :input OR ponumber = :input OR UPPER(bilname) LIKE UPPER(''%'' || :input || ''%'')',
        p_items_per_page => 25
    );
    COMMIT;
END;
/

-- PERFORMANCE OPTIMIZATION TIPS:

-- 1. Create composite indexes for common search patterns
/*
CREATE INDEX idx_oeshih_shiuniq_shinumber ON SFLDAT.OESHIH(shiuniq, shinumber);
CREATE INDEX idx_oeshih_customer_ponumber ON SFLDAT.OESHIH(customer, ponumber);
*/

-- 2. Use function-based indexes for case-insensitive search
/*
CREATE INDEX idx_oeshih_bilname_upper ON SFLDAT.OESHIH(UPPER(bilname));
*/

-- 3. Consider partitioning for large tables
/*
-- Partition by date or other logical criteria
*/

-- 4. Use hints for specific execution plans
SELECT /*+ INDEX(oeshih idx_oeshih_shiuniq) */ * 
FROM SFLDAT.OESHIH
WHERE shiuniq = :input

-- 5. Cache frequently accessed data
-- Consider using Oracle Result Cache or application-level caching

-- USAGE EXAMPLES:
-- For numeric search: /ords/salesforceext/sfldat/oeshih/numeric?input=12345
-- For text search: /ords/salesforceext/sfldat/oeshih/text?input=CUST001
-- For smart search: /ords/salesforceext/sfldat/oeshih?input=12345 (auto-detects type)