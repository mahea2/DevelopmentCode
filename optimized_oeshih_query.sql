-- Optimized OESHIH query solutions for better performance

-- PROBLEM: Multiple OR conditions cause poor performance
-- Each OR condition can trigger a separate table scan
-- LIKE with wildcards prevents index usage
-- No proper indexing strategy

-- SOLUTION 1: Use UNION ALL for better performance (RECOMMENDED)
-- This allows Oracle to use indexes on each individual column
SELECT * FROM SFLDAT.OESHIH WHERE shiuniq = :input
UNION ALL
SELECT * FROM SFLDAT.OESHIH WHERE shinumber = :input AND shiuniq != :input
UNION ALL
SELECT * FROM SFLDAT.OESHIH WHERE customer = :input AND shiuniq != :input AND shinumber != :input
UNION ALL
SELECT * FROM SFLDAT.OESHIH WHERE ponumber = :input AND shiuniq != :input AND shinumber != :input AND customer != :input
UNION ALL
SELECT * FROM SFLDAT.OESHIH WHERE lastinvnum = :input AND shiuniq != :input AND shinumber != :input AND customer != :input AND ponumber != :input
UNION ALL
SELECT * FROM SFLDAT.OESHIH WHERE UPPER(bilname) LIKE UPPER('%' || :input || '%') 
    AND shiuniq != :input AND shinumber != :input AND customer != :input AND ponumber != :input AND lastinvnum != :input
WHERE (:input IS NOT NULL AND :input != '')

-- SOLUTION 2: Use CASE WHEN for conditional logic (Better than OR)
SELECT * 
FROM SFLDAT.OESHIH
WHERE CASE 
    WHEN :input IS NULL OR :input = '' THEN 1
    WHEN shiuniq = :input THEN 1
    WHEN shinumber = :input THEN 1
    WHEN customer = :input THEN 1
    WHEN ponumber = :input THEN 1
    WHEN lastinvnum = :input THEN 1
    WHEN UPPER(bilname) LIKE UPPER('%' || :input || '%') THEN 1
    ELSE 0
END = 1

-- SOLUTION 3: Separate endpoints for different search types (BEST PERFORMANCE)
-- Create different API endpoints for different search types

-- Endpoint 1: Search by shiuniq (exact match)
SELECT * FROM SFLDAT.OESHIH WHERE shiuniq = :input

-- Endpoint 2: Search by shinumber (exact match)
SELECT * FROM SFLDAT.OESHIH WHERE shinumber = :input

-- Endpoint 3: Search by customer (exact match)
SELECT * FROM SFLDAT.OESHIH WHERE customer = :input

-- Endpoint 4: Search by bilname (partial match)
SELECT * FROM SFLDAT.OESHIH WHERE UPPER(bilname) LIKE UPPER('%' || :input || '%')

-- SOLUTION 4: Use function-based indexes for better performance
-- Create these indexes first:
/*
CREATE INDEX idx_oeshih_shiuniq ON SFLDAT.OESHIH(shiuniq);
CREATE INDEX idx_oeshih_shinumber ON SFLDAT.OESHIH(shinumber);
CREATE INDEX idx_oeshih_customer ON SFLDAT.OESHIH(customer);
CREATE INDEX idx_oeshih_ponumber ON SFLDAT.OESHIH(ponumber);
CREATE INDEX idx_oeshih_lastinvnum ON SFLDAT.OESHIH(lastinvnum);
CREATE INDEX idx_oeshih_bilname_upper ON SFLDAT.OESHIH(UPPER(bilname));
*/

-- Then use this optimized query:
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR shiuniq = :input
   OR shinumber = :input
   OR customer = :input
   OR ponumber = :input
   OR lastinvnum = :input
   OR UPPER(bilname) LIKE UPPER('%' || :input || '%')

-- SOLUTION 5: Use Oracle Text for full-text search (BEST FOR TEXT SEARCH)
-- First, create a text index:
/*
CREATE INDEX oeshih_text_idx ON SFLDAT.OESHIH(bilname) 
INDEXTYPE IS CTXSYS.CONTEXT;
*/

-- Then use CONTAINS for text search:
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR shiuniq = :input
   OR shinumber = :input
   OR customer = :input
   OR ponumber = :input
   OR lastinvnum = :input
   OR CONTAINS(bilname, :input) > 0

-- SOLUTION 6: Hybrid approach - Use different strategies based on input type
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR (
       -- For numeric-looking input, search numeric fields first
       CASE 
           WHEN REGEXP_LIKE(:input, '^[0-9]+$') THEN
               shiuniq = :input OR shinumber = :input OR lastinvnum = :input
           ELSE
               customer = :input OR ponumber = :input OR UPPER(bilname) LIKE UPPER('%' || :input || '%')
       END
   )

-- RECOMMENDED IMPLEMENTATION FOR ORDS:
-- Use separate endpoints for better performance

-- Endpoint 1: Search by exact match (fastest)
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeshih/exact',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_collection_feed,
        p_source         => 'SELECT * FROM SFLDAT.OESHIH WHERE shiuniq = :input OR shinumber = :input OR customer = :input OR ponumber = :input OR lastinvnum = :input',
        p_items_per_page => 25
    );
    COMMIT;
END;
/

-- Endpoint 2: Search by text (slower but necessary)
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeshih/text',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_collection_feed,
        p_source         => 'SELECT * FROM SFLDAT.OESHIH WHERE UPPER(bilname) LIKE UPPER(''%'' || :input || ''%'')',
        p_items_per_page => 25
    );
    COMMIT;
END;
/

-- PERFORMANCE TIPS:
-- 1. Create indexes on all search columns
-- 2. Use separate endpoints for different search types
-- 3. Consider Oracle Text for full-text search
-- 4. Use UNION ALL instead of OR when possible
-- 5. Limit result sets with pagination
-- 6. Consider caching frequently searched values