-- Analysis of the OEINVD query issues and solutions

-- Original query with issues:
/*
SELECT * 
FROM SFLDAT.OEINVD
WHERE 
    (:invuniq IS NULL OR invuniq = :invuniq)
    AND (:item IS NULL OR item = :item)
    AND (:desc IS NULL OR LOWER(desc) LIKE LOWER('%' || :desc || '%'))
*/

-- ISSUE 1: 'desc' is a reserved keyword in Oracle
-- Oracle reserves 'desc' for ORDER BY DESC clause
-- This can cause syntax errors or unexpected behavior

-- ISSUE 2: Empty string handling
-- The query doesn't handle empty strings properly
-- When :invuniq = '' or :item = '' or :desc = '', it should be treated as NULL

-- ISSUE 3: Case sensitivity in LIKE comparison
-- Using LOWER() on both sides is redundant and can impact performance

-- CORRECTED VERSION 1: Handle reserved keyword and empty strings
SELECT * 
FROM SFLDAT.OEINVD
WHERE 
    (:invuniq IS NULL OR :invuniq = '' OR invuniq = :invuniq)
    AND (:item IS NULL OR :item = '' OR item = :item)
    AND (:desc IS NULL OR :desc = '' OR LOWER("desc") LIKE LOWER('%' || :desc || '%'))

-- CORRECTED VERSION 2: Better performance with proper indexing
SELECT * 
FROM SFLDAT.OEINVD
WHERE 
    (:invuniq IS NULL OR :invuniq = '' OR invuniq = :invuniq)
    AND (:item IS NULL OR :item = '' OR item = :item)
    AND (:desc IS NULL OR :desc = '' OR "desc" LIKE '%' || :desc || '%')

-- CORRECTED VERSION 3: Case-insensitive search with better performance
SELECT * 
FROM SFLDAT.OEINVD
WHERE 
    (:invuniq IS NULL OR :invuniq = '' OR invuniq = :invuniq)
    AND (:item IS NULL OR :item = '' OR item = :item)
    AND (:desc IS NULL OR :desc = '' OR UPPER("desc") LIKE UPPER('%' || :desc || '%'))

-- ALTERNATIVE: Using REGEXP_LIKE for more flexible search
SELECT * 
FROM SFLDAT.OEINVD
WHERE 
    (:invuniq IS NULL OR :invuniq = '' OR invuniq = :invuniq)
    AND (:item IS NULL OR :item = '' OR item = :item)
    AND (:desc IS NULL OR :desc = '' OR REGEXP_LIKE("desc", :desc, 'i'))

-- RECOMMENDED VERSION: Most robust and performant
SELECT * 
FROM SFLDAT.OEINVD
WHERE 
    (:invuniq IS NULL OR :invuniq = '' OR invuniq = :invuniq)
    AND (:item IS NULL OR :item = '' OR item = :item)
    AND (:desc IS NULL OR :desc = '' OR "desc" LIKE '%' || :desc || '%')

-- For ORDS API, use this in your handler:
/*
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeinvd',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_collection_feed,
        p_source         => 'SELECT * FROM SFLDAT.OEINVD WHERE (:invuniq IS NULL OR :invuniq = '''' OR invuniq = :invuniq) AND (:item IS NULL OR :item = '''' OR item = :item) AND (:desc IS NULL OR :desc = '''' OR "desc" LIKE ''%'' || :desc || ''%'')',
        p_items_per_page => 25
    );
    COMMIT;
END;
/
*/