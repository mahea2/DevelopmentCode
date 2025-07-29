-- Fixed OESHIH query to handle ORA-01722 data type conversion errors

-- PROBLEM: ORA-01722 occurs when comparing string input with numeric columns
-- Columns like shiuniq, shinumber, lastinvnum are likely numeric
-- When :input is a string, Oracle can't convert it to number for comparison

-- SOLUTION 1: Convert numeric columns to strings for comparison (SAFEST)
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR TO_CHAR(shiuniq) = :input
   OR TO_CHAR(shinumber) = :input
   OR customer = :input
   OR ponumber = :input
   OR TO_CHAR(lastinvnum) = :input
   OR UPPER(bilname) LIKE UPPER('%' || :input || '%')

-- SOLUTION 2: Use CASE WHEN to handle data type conversion safely
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR CASE 
       WHEN REGEXP_LIKE(:input, '^[0-9]+$') THEN
           -- Input is numeric, compare with numeric fields
           shiuniq = TO_NUMBER(:input) 
           OR shinumber = TO_NUMBER(:input) 
           OR lastinvnum = TO_NUMBER(:input)
       ELSE
           -- Input is string, compare with string fields
           customer = :input 
           OR ponumber = :input 
           OR UPPER(bilname) LIKE UPPER('%' || :input || '%')
       END

-- SOLUTION 3: Separate numeric and string comparisons (RECOMMENDED)
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR (
       -- Try numeric comparison first (if input looks like a number)
       CASE 
           WHEN REGEXP_LIKE(:input, '^[0-9]+$') THEN
               shiuniq = TO_NUMBER(:input) 
               OR shinumber = TO_NUMBER(:input) 
               OR lastinvnum = TO_NUMBER(:input)
           ELSE 0
       END = 1
   )
   OR (
       -- String comparisons
       customer = :input 
       OR ponumber = :input 
       OR UPPER(bilname) LIKE UPPER('%' || :input || '%')
   )

-- SOLUTION 4: Use NVL to handle NULL conversions safely
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR TO_CHAR(NVL(shiuniq, 0)) = :input
   OR TO_CHAR(NVL(shinumber, 0)) = :input
   OR customer = :input
   OR ponumber = :input
   OR TO_CHAR(NVL(lastinvnum, 0)) = :input
   OR UPPER(bilname) LIKE UPPER('%' || :input || '%')

-- SOLUTION 5: Most robust - handle all possible data types
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR (
       -- Try to convert to number and compare with numeric fields
       CASE 
           WHEN REGEXP_LIKE(:input, '^[0-9]+$') THEN
               CASE 
                   WHEN shiuniq = TO_NUMBER(:input) THEN 1
                   WHEN shinumber = TO_NUMBER(:input) THEN 1
                   WHEN lastinvnum = TO_NUMBER(:input) THEN 1
                   ELSE 0
               END
           ELSE 0
       END = 1
   )
   OR (
       -- String comparisons
       customer = :input 
       OR ponumber = :input 
       OR UPPER(bilname) LIKE UPPER('%' || :input || '%')
   )

-- RECOMMENDED VERSION FOR ORDS API:
-- This handles all data types safely and prevents ORA-01722
SELECT * 
FROM SFLDAT.OESHIH
WHERE (:input IS NULL OR :input = '')
   OR TO_CHAR(shiuniq) = :input
   OR TO_CHAR(shinumber) = :input
   OR customer = :input
   OR ponumber = :input
   OR TO_CHAR(lastinvnum) = :input
   OR UPPER(bilname) LIKE UPPER('%' || :input || '%')

-- For ORDS handler, use this:
/*
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeshih',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_collection_feed,
        p_source         => 'SELECT * FROM SFLDAT.OESHIH WHERE (:input IS NULL OR :input = '''') OR TO_CHAR(shiuniq) = :input OR TO_CHAR(shinumber) = :input OR customer = :input OR ponumber = :input OR TO_CHAR(lastinvnum) = :input OR UPPER(bilname) LIKE UPPER(''%'' || :input || ''%'')',
        p_items_per_page => 25
    );
    COMMIT;
END;
/
*/

-- ALTERNATIVE: Create separate endpoints for different data types

-- Endpoint 1: For numeric searches
SELECT * FROM SFLDAT.OESHIH 
WHERE REGEXP_LIKE(:input, '^[0-9]+$')
  AND (shiuniq = TO_NUMBER(:input) 
       OR shinumber = TO_NUMBER(:input) 
       OR lastinvnum = TO_NUMBER(:input))

-- Endpoint 2: For string searches
SELECT * FROM SFLDAT.OESHIH 
WHERE customer = :input 
   OR ponumber = :input 
   OR UPPER(bilname) LIKE UPPER('%' || :input || '%')

-- TEST CASES:
-- 1. :input = '12345' -> Will search numeric fields
-- 2. :input = 'CUST001' -> Will search string fields
-- 3. :input = 'John' -> Will search bilname and string fields
-- 4. :input = NULL or '' -> Returns all records