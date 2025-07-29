-- Final Hybrid Search with Correct Column Names
-- Requirements implemented:
-- 1. Match DESC or SYNONYMS in AI_ICITEM
-- 2. Prioritize BALAR brand from ICITEMO with QTYONHAND from ICILOC  
-- 3. Use OEINVH and OEINVD for customer purchase history
-- Updated with correct column names: item, invuniq, customer, unitcost

SET SERVEROUTPUT ON;

DECLARE
    -- Configuration
    v_search_term       VARCHAR2(100) := 'ice cubes';
    v_customer_id       VARCHAR2(20)  := 'CUST001';
    v_top_n             INTEGER       := 10;
    v_page_number       INTEGER       := 1;
    v_days_lookback     INTEGER       := 365;

    -- Variables
    v_query_vector      VECTOR;
    v_count             INTEGER       := 0;
    v_offset            INTEGER;

BEGIN
    -- Validation
    IF v_search_term IS NULL OR LENGTH(TRIM(v_search_term)) = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Search term cannot be empty.');
        RETURN;
    END IF;

    -- Setup
    v_offset := (v_page_number - 1) * v_top_n;
    
    -- Smart spell correction for common typos
    v_search_term := CASE 
        WHEN UPPER(v_search_term) LIKE '%ICE CUE%' THEN REPLACE(UPPER(v_search_term), 'ICE CUE', 'ICE CUBE')
        WHEN UPPER(v_search_term) LIKE '%ICES%' THEN REPLACE(UPPER(v_search_term), 'ICES', 'ICE')
        WHEN UPPER(v_search_term) LIKE '%CUEB%' THEN REPLACE(UPPER(v_search_term), 'CUEB', 'CUBE')
        WHEN UPPER(v_search_term) LIKE '%CUVE%' THEN REPLACE(UPPER(v_search_term), 'CUVE', 'CUBE')
        WHEN UPPER(v_search_term) LIKE '%CUDE%' THEN REPLACE(UPPER(v_search_term), 'CUDE', 'CUBE')
        WHEN UPPER(v_search_term) LIKE '%REFRIGERAT%' THEN REPLACE(UPPER(v_search_term), 'REFRIGERAT', 'REFRIGERATOR')
        WHEN UPPER(v_search_term) LIKE '%FREEZ%' THEN REPLACE(UPPER(v_search_term), 'FREEZ', 'FREEZER')
        ELSE v_search_term
    END;

    DBMS_OUTPUT.PUT_LINE('=== HYBRID SEARCH ===');
    IF v_search_term != TRIM(v_search_term) THEN
        DBMS_OUTPUT.PUT_LINE('Original Search: "' || TRIM(v_search_term) || '" → Corrected to: "' || v_search_term || '"');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Search Term: "' || v_search_term || '"');
    END IF;
    DBMS_OUTPUT.PUT_LINE('Customer: ' || v_customer_id);
    DBMS_OUTPUT.PUT_LINE('Days Lookback: ' || v_days_lookback);
    DBMS_OUTPUT.PUT_LINE('Results Per Page: ' || v_top_n);
    DBMS_OUTPUT.PUT_LINE('');

    -- Generate vector
    BEGIN
        v_query_vector := dbms_vector.utl_to_embedding(
            v_search_term,
            json('{
                "provider": "OpenAI",
                "credential_name": "OPENAI_CRED1",
                "url": "https://api.openai.com/v1/embeddings",
                "model": "text-embedding-3-small"
            }')
        );
        DBMS_OUTPUT.PUT_LINE('✓ Vector generated successfully');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('✗ Vector error: ' || SQLERRM);
            RETURN;
    END;

    -- Execute search using direct FOR loop
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SEARCH RESULTS ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('ITEM NUMBER', 15) || ' | ' || RPAD('DESCRIPTION', 50) || ' | ' || LPAD('QUANTITY', 10));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 15, '-') || ' | ' || RPAD('-', 50, '-') || ' | ' || RPAD('-', 10, '-'));
    
    BEGIN
        -- Direct search using FOR loop to avoid cursor syntax issues
        FOR rec IN (
            WITH customer_history AS (
                -- Customer purchase history from OEINVH and OEINVD with correct column names
                SELECT 
                    d.item,
                    COUNT(DISTINCT h.invuniq) as order_count,
                    SUM(d.qtyshipped) as total_qty_purchased,
                    MAX(h.invdate) as last_purchase_date,
                    SUM(d.unitcost) as total_amount_spent,
                    -- Recency scoring based on last purchase date (converting numeric date)
                    CASE 
                        WHEN TO_DATE(TO_CHAR(MAX(h.invdate)), 'YYYYMMDD') >= SYSDATE - 30 THEN 50   -- Very recent (last 30 days)
                        WHEN TO_DATE(TO_CHAR(MAX(h.invdate)), 'YYYYMMDD') >= SYSDATE - 90 THEN 40   -- Recent (last 3 months)
                        WHEN TO_DATE(TO_CHAR(MAX(h.invdate)), 'YYYYMMDD') >= SYSDATE - 180 THEN 30  -- Medium recent (last 6 months)
                        WHEN TO_DATE(TO_CHAR(MAX(h.invdate)), 'YYYYMMDD') >= SYSDATE - 365 THEN 20  -- Within last year
                        ELSE 10                                        -- Older purchases
                    END as recency_score,
                    -- Frequency scoring based on number of orders
                    CASE 
                        WHEN COUNT(DISTINCT h.invuniq) >= 5 THEN 30   -- Frequent buyer (5+ orders)
                        WHEN COUNT(DISTINCT h.invuniq) >= 3 THEN 20   -- Regular buyer (3-4 orders)
                        WHEN COUNT(DISTINCT h.invuniq) >= 2 THEN 10   -- Occasional buyer (2 orders)
                        ELSE 5                                         -- Single purchase
                    END as frequency_score
                FROM SFLDAT.OEINVH h
                INNER JOIN SFLDAT.OEINVD d ON h.invuniq = d.invuniq
                WHERE h.customer = v_customer_id
                AND TO_DATE(TO_CHAR(h.invdate), 'YYYYMMDD') >= SYSDATE - v_days_lookback
                AND d.qtyshipped > 0
                AND d.unitcost > 0
                GROUP BY d.item
            ),
            scored_items AS (
                SELECT
                    ai.itemno,
                    ai."DESC",
                    ai.SYNONYMS,
                    
                    -- Step 1: Smart text matching with typo tolerance
                    CASE
                        -- Exact matches (highest priority)
                        WHEN UPPER(ai."DESC") = UPPER(v_search_term) THEN 100                    
                        WHEN ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) = UPPER(v_search_term) THEN 100  
                        
                        -- Starts with search term (very relevant)
                        WHEN UPPER(ai."DESC") LIKE UPPER(v_search_term) || '%' THEN 90           
                        WHEN ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE UPPER(v_search_term) || '%' THEN 90
                        
                        -- Contains complete search term (relevant)
                        WHEN UPPER(ai."DESC") LIKE '%' || UPPER(v_search_term) || '%' THEN 80    
                        WHEN ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE '%' || UPPER(v_search_term) || '%' THEN 80
                        
                        -- Word boundary matches (precise matching)
                        WHEN REGEXP_LIKE(UPPER(ai."DESC"), '\b' || UPPER(v_search_term) || '\b') THEN 70     
                        WHEN ai.SYNONYMS IS NOT NULL AND REGEXP_LIKE(UPPER(ai.SYNONYMS), '\b' || UPPER(v_search_term) || '\b') THEN 70
                        
                        -- Smart typo handling for common mistakes
                        WHEN UPPER(v_search_term) LIKE '%ICE CUE%' AND UPPER(ai."DESC") LIKE '%ICE CUBE%' THEN 75
                        WHEN UPPER(v_search_term) LIKE '%CUEB%' AND UPPER(ai."DESC") LIKE '%CUBE%' THEN 65
                        WHEN UPPER(v_search_term) LIKE '%CUVE%' AND UPPER(ai."DESC") LIKE '%CUBE%' THEN 65
                        WHEN UPPER(v_search_term) LIKE '%CUDE%' AND UPPER(ai."DESC") LIKE '%CUBE%' THEN 65
                        WHEN UPPER(v_search_term) LIKE '%FREEZ%' AND UPPER(ai."DESC") LIKE '%FREEZE%' THEN 65
                        
                        -- High similarity matching for close typos (using Oracle's built-in)
                        WHEN UTL_MATCH.JARO_WINKLER_SIMILARITY(UPPER(ai."DESC"), UPPER(v_search_term)) >= 0.85 THEN 60
                        WHEN ai.SYNONYMS IS NOT NULL AND UTL_MATCH.JARO_WINKLER_SIMILARITY(UPPER(ai.SYNONYMS), UPPER(v_search_term)) >= 0.85 THEN 60
                        
                        -- SOUNDEX matching for phonetically similar words
                        WHEN SOUNDEX(UPPER(ai."DESC")) = SOUNDEX(UPPER(v_search_term)) THEN 50
                        WHEN ai.SYNONYMS IS NOT NULL AND SOUNDEX(UPPER(ai.SYNONYMS)) = SOUNDEX(UPPER(v_search_term)) THEN 50
                        
                        ELSE 0
                    END AS text_match_score,
                    
                    -- Step 2: BALAR brand prioritization from ICITEMO
                    CASE
                        WHEN UPPER(brand.value) IN ('BALAR', 'BALARS') THEN 100  -- BALAR brand gets highest priority
                        WHEN brand.value IS NOT NULL THEN 20                     -- Other brands get some points
                        ELSE 0                                                    -- No brand info
                    END AS brand_score,
                    
                    -- Step 2: Stock availability from ICILOC with graduated scoring
                    CASE 
                        WHEN stock.total_qty > 100 THEN 50    -- High stock
                        WHEN stock.total_qty > 50 THEN 40     -- Good stock
                        WHEN stock.total_qty > 25 THEN 30     -- Medium stock
                        WHEN stock.total_qty > 10 THEN 20     -- Low stock
                        WHEN stock.total_qty > 0 THEN 10      -- Very low stock
                        ELSE 0                                 -- Out of stock
                    END AS stock_score,
                    
                    -- Step 3: Customer history scoring (RFM - Recency + Frequency)
                    (COALESCE(ch.recency_score, 0) + COALESCE(ch.frequency_score, 0)) AS history_score,
                    
                    -- Vector similarity for semantic matching (handle NULL vectors)
                    CASE 
                        WHEN ai.vector_desc IS NOT NULL THEN 
                            (1 - vector_distance(ai.vector_desc, v_query_vector, COSINE)) * 100
                        ELSE 0
                    END AS similarity_score,
                    
                    -- Display data for output
                    COALESCE(stock.total_qty, 0) AS stock_qty,
                    COALESCE(brand.value, 'Unknown') AS brand_name,
                    COALESCE(ch.order_count, 0) AS customer_orders,
                    COALESCE(TO_DATE(TO_CHAR(ch.last_purchase_date), 'YYYYMMDD'), TO_DATE('1900-01-01', 'YYYY-MM-DD')) AS last_purchase,
                    COALESCE(ch.total_amount_spent, 0) AS customer_spent
                    
                FROM AI_ICITEM ai
                
                -- Join brand information from ICITEMO
                LEFT JOIN (
                    SELECT itemno, value
                    FROM SFLDAT.ICITEMO 
                    WHERE optfield = 'BRAND'
                ) brand ON ai.itemno = brand.itemno
                
                -- Join stock information from ICILOC
                LEFT JOIN (
                    SELECT itemno, SUM(GREATEST(QTYONHAND, 0)) as total_qty
                    FROM SFLDAT.ICILOC
                    GROUP BY itemno
                ) stock ON ai.itemno = stock.itemno
                
                -- Join customer history (using correct column name 'item')
                LEFT JOIN customer_history ch ON ai.itemno = ch.item
                
                WHERE ai."DESC" IS NOT NULL
                AND LENGTH(TRIM(ai."DESC")) > 0
                -- Smart filter: Exact matches + typo tolerance
                AND (
                    -- Primary: Direct text matches in description
                    (UPPER(ai."DESC") LIKE '%' || UPPER(v_search_term) || '%') OR
                    -- Primary: Direct text matches in synonyms
                    (ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE '%' || UPPER(v_search_term) || '%') OR
                    -- Typo-tolerant matching for common mistakes
                    (UPPER(v_search_term) LIKE '%ICE CUE%' AND UPPER(ai."DESC") LIKE '%ICE CUBE%') OR
                    (UPPER(v_search_term) LIKE '%CUEB%' AND UPPER(ai."DESC") LIKE '%CUBE%') OR
                    (UPPER(v_search_term) LIKE '%CUVE%' AND UPPER(ai."DESC") LIKE '%CUBE%') OR
                    (UPPER(v_search_term) LIKE '%CUDE%' AND UPPER(ai."DESC") LIKE '%CUBE%') OR
                    (UPPER(v_search_term) LIKE '%FREEZ%' AND UPPER(ai."DESC") LIKE '%FREEZE%') OR
                    -- High similarity for close typos
                    (UTL_MATCH.JARO_WINKLER_SIMILARITY(UPPER(ai."DESC"), UPPER(v_search_term)) >= 0.85) OR
                    (ai.SYNONYMS IS NOT NULL AND UTL_MATCH.JARO_WINKLER_SIMILARITY(UPPER(ai.SYNONYMS), UPPER(v_search_term)) >= 0.85) OR
                    -- SOUNDEX for phonetic similarity
                    (SOUNDEX(UPPER(ai."DESC")) = SOUNDEX(UPPER(v_search_term))) OR
                    (ai.SYNONYMS IS NOT NULL AND SOUNDEX(UPPER(ai.SYNONYMS)) = SOUNDEX(UPPER(v_search_term))) OR
                    -- Secondary: Vector similarity for semantic matches (if vector exists)
                    (ai.vector_desc IS NOT NULL AND (1 - vector_distance(ai.vector_desc, v_query_vector, COSINE)) >= 0.4) OR
                    -- Tertiary: Customer purchase history items
                    (ch.item IS NOT NULL)
                )
            )
            SELECT
                itemno,
                "DESC",
                SYNONYMS,
                brand_name,
                
                -- Weighted total score calculation with business priorities
                (
                    text_match_score * 1.5 +     -- Highest priority: exact text matching
                    history_score * 1.8 +        -- Highest priority: customer purchase history  
                    brand_score * 1.2 +          -- High priority: BALAR brand preference
                    stock_score * 1.0 +          -- Medium priority: stock availability
                    similarity_score * 0.8       -- Lower priority: vector similarity
                ) AS total_score,
                
                -- Individual score components for transparency
                text_match_score,
                brand_score,
                history_score,
                stock_score,
                ROUND(similarity_score, 1) as similarity_score,
                stock_qty,
                customer_orders,
                last_purchase,
                customer_spent,
                
                -- Recommendation type classification
                CASE 
                    WHEN customer_orders > 0 THEN 'REPURCHASE'        -- Customer bought this before
                    WHEN brand_score = 100 THEN 'BALAR_BRAND'         -- BALAR brand item
                    WHEN text_match_score >= 80 THEN 'EXACT_MATCH'    -- Exact text match
                    WHEN text_match_score >= 65 THEN 'PARTIAL_MATCH'  -- Partial text match
                    ELSE 'SIMILARITY'                                  -- Vector similarity match
                END AS rec_type
                
            FROM scored_items
            WHERE (text_match_score + history_score + similarity_score) > 15  -- Focused threshold for quality results
            AND (text_match_score > 0 OR history_score > 10 OR similarity_score > 40)  -- Ensure real relevance
            ORDER BY
                total_score DESC,        -- Primary: highest total score
                history_score DESC,      -- Secondary: customer history
                brand_score DESC,        -- Tertiary: BALAR brand preference
                text_match_score DESC,   -- Quaternary: text matching
                stock_qty DESC,          -- Quinary: stock availability
                itemno ASC              -- Final: consistent ordering
            OFFSET v_offset ROWS
            FETCH NEXT v_top_n ROWS ONLY
        ) LOOP
            v_count := v_count + 1;
            
            -- Simple display format: Item Number | Description | Quantity
            DBMS_OUTPUT.PUT_LINE(
                RPAD(rec.itemno, 15) || ' | ' ||
                RPAD(SUBSTR(rec."DESC", 1, 50), 50) || ' | ' ||
                LPAD('QTY: ' || rec.stock_qty, 10)
            );
        END LOOP;
        
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('✗ Search error: ' || SQLERRM);
            RETURN;
    END;

    -- Results summary
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SUMMARY ===');
    DBMS_OUTPUT.PUT_LINE('Results Found: ' || v_count);
    
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('No results found. Suggestions:');
        DBMS_OUTPUT.PUT_LINE('• Try different search terms or synonyms');
        DBMS_OUTPUT.PUT_LINE('• Check if customer has purchase history');
        DBMS_OUTPUT.PUT_LINE('• Verify items have vector embeddings');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Search completed successfully with intelligent ranking:');
        DBMS_OUTPUT.PUT_LINE('• Customer purchase history prioritized');
        DBMS_OUTPUT.PUT_LINE('• BALAR brand items highlighted');
        DBMS_OUTPUT.PUT_LINE('• Stock availability considered');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('=== SYSTEM ERROR ===');
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Please check table access and data availability.');
END;
/