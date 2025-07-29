-- Oracle ADW ORDS API Solution for OEINVH table
-- This provides the correct SQL logic for handling optional parameters

-- Option 1: Using CASE WHEN for conditional filtering
SELECT * 
FROM SFLDAT.OEINVH 
WHERE (CASE 
    WHEN :invuniq IS NOT NULL AND :invuniq != '' THEN 
        CASE WHEN invuniq = :invuniq THEN 1 ELSE 0 END
    WHEN :customer IS NOT NULL AND :customer != '' THEN 
        CASE WHEN customer = :customer THEN 1 ELSE 0 END
    ELSE 1  -- Return all records when no parameters provided
END) = 1;

-- Option 2: Using NVL with proper conditional logic (Recommended)
SELECT * 
FROM SFLDAT.OEINVH 
WHERE (:invuniq IS NULL OR :invuniq = '' OR invuniq = :invuniq)
  AND (:customer IS NULL OR :customer = '' OR customer = :customer);

-- Option 3: Most explicit and readable approach
SELECT * 
FROM SFLDAT.OEINVH 
WHERE (:invuniq IS NULL OR :invuniq = '' OR invuniq = :invuniq)
  AND (:customer IS NULL OR :customer = '' OR customer = :customer);

-- For ORDS REST API, you would use this in your handler:
/*
CREATE OR REPLACE PROCEDURE get_oeinvh(
    p_invuniq IN VARCHAR2 DEFAULT NULL,
    p_customer IN VARCHAR2 DEFAULT NULL,
    p_result OUT SYS_REFCURSOR
) AS
BEGIN
    OPEN p_result FOR
        SELECT * 
        FROM SFLDAT.OEINVH 
        WHERE (p_invuniq IS NULL OR p_invuniq = '' OR invuniq = p_invuniq)
          AND (p_customer IS NULL OR p_customer = '' OR customer = p_customer);
END;
/
*/

-- Example ORDS handler configuration:
/*
BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name    => 'salesforceext',
        p_pattern        => 'sfldat/oeinvh',
        p_method         => 'GET',
        p_source_type    => ORDS.source_type_collection_feed,
        p_source         => 'SELECT * FROM SFLDAT.OEINVH WHERE (:invuniq IS NULL OR :invuniq = '''' OR invuniq = :invuniq) AND (:customer IS NULL OR :customer = '''' OR customer = :customer)',
        p_items_per_page => 25
    );
    
    COMMIT;
END;
/
*/