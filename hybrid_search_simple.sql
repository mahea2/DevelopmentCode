-- Simple Hybrid Search - No Cursor Syntax Issues
-- Following exact requirements:
-- 1. Match DESC or SYNONYMS in AI_ICITEM
-- 2. Prioritize BALAR brand from ICITEMO with QTYONHAND from ICILOC  
-- 3. Use OEINVH and OEINVD for customer purchase history

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
    v_sql               CLOB;

BEGIN
    -- Validation
    IF v_search_term IS NULL OR LENGTH(TRIM(v_search_term)) = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Search term cannot be empty.');
        RETURN;
    END IF;

    -- Setup
    v_offset := (v_page_number - 1) * v_top_n;

    DBMS_OUTPUT.PUT_LINE('=== HYBRID SEARCH ===');
    DBMS_OUTPUT.PUT_LINE('Search Term: "' || v_search_term || '"');
    DBMS_OUTPUT.PUT_LINE('Customer: ' || v_customer_id);
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
                -- Customer purchase history from OEINVH and OEINVD
                SELECT 
                    d.itemno,
                    COUNT(DISTINCT h.invno) as order_count,
                    SUM(d.qtyshipped) as total_qty_purchased,
                    MAX(h.invdate) as last_purchase_date,
                    SUM(d.amount) as total_amount_spent,
                    -- Recency scoring
                    CASE 
                        WHEN MAX(h.invdate) >= SYSDATE - 30 THEN 50
                        WHEN MAX(h.invdate) >= SYSDATE - 90 THEN 40
                        WHEN MAX(h.invdate) >= SYSDATE - 180 THEN 30
                        WHEN MAX(h.invdate) >= SYSDATE - 365 THEN 20
                        ELSE 10
                    END as recency_score,
                    -- Frequency scoring
                    CASE 
                        WHEN COUNT(DISTINCT h.invno) >= 5 THEN 30
                        WHEN COUNT(DISTINCT h.invno) >= 3 THEN 20
                        WHEN COUNT(DISTINCT h.invno) >= 2 THEN 10
                        ELSE 5
                    END as frequency_score
                FROM SFLDAT.OEINVH h
                INNER JOIN SFLDAT.OEINVD d ON h.invno = d.invno
                WHERE h.custno = v_customer_id
                AND h.invdate >= SYSDATE - v_days_lookback
                AND d.qtyshipped > 0
                AND d.amount > 0
                GROUP BY d.itemno
            ),
            scored_items AS (
                SELECT
                    ai.itemno,
                    ai."DESC",
                    ai.SYNONYMS,
                    
                    -- Step 1: Text matching (DESC and SYNONYMS)
                    CASE
                        WHEN UPPER(ai."DESC") = UPPER(v_search_term) THEN 100
                        WHEN UPPER(ai."DESC") LIKE UPPER(v_search_term) || '%' THEN 90
                        WHEN UPPER(ai."DESC") LIKE '%' || UPPER(v_search_term) || '%' THEN 80
                        WHEN ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) = UPPER(v_search_term) THEN 95
                        WHEN ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE '%' || UPPER(v_search_term) || '%' THEN 75
                        WHEN REGEXP_LIKE(UPPER(ai."DESC"), '\b' || UPPER(v_search_term) || '\b') THEN 70
                        WHEN ai.SYNONYMS IS NOT NULL AND REGEXP_LIKE(UPPER(ai.SYNONYMS), '\b' || UPPER(v_search_term) || '\b') THEN 65
                        ELSE 0
                    END AS text_match_score,
                    
                    -- Step 2: BALAR brand prioritization
                    CASE
                        WHEN UPPER(brand.value) IN ('BALAR', 'BALARS') THEN 100
                        WHEN brand.value IS NOT NULL THEN 20
                        ELSE 0
                    END AS brand_score,
                    
                    -- Step 2: Stock availability from ICILOC
                    CASE 
                        WHEN stock.total_qty > 100 THEN 50
                        WHEN stock.total_qty > 50 THEN 40
                        WHEN stock.total_qty > 25 THEN 30
                        WHEN stock.total_qty > 10 THEN 20
                        WHEN stock.total_qty > 0 THEN 10
                        ELSE 0
                    END AS stock_score,
                    
                    -- Step 3: Customer history scoring
                    (COALESCE(ch.recency_score, 0) + COALESCE(ch.frequency_score, 0)) AS history_score,
                    
                    -- Vector similarity
                    (1 - vector_distance(ai.vector_desc, v_query_vector, COSINE)) * 100 AS similarity_score,
                    
                    -- Display data
                    COALESCE(stock.total_qty, 0) AS stock_qty,
                    COALESCE(brand.value, 'Unknown') AS brand_name,
                    COALESCE(ch.order_count, 0) AS customer_orders,
                    COALESCE(ch.last_purchase_date, TO_DATE('1900-01-01', 'YYYY-MM-DD')) AS last_purchase
                    
                FROM AI_ICITEM ai
                
                LEFT JOIN (
                    SELECT itemno, value
                    FROM SFLDAT.ICITEMO 
                    WHERE optfield = 'BRAND'
                ) brand ON ai.itemno = brand.itemno
                
                LEFT JOIN (
                    SELECT itemno, SUM(GREATEST(QTYONHAND, 0)) as total_qty
                    FROM SFLDAT.ICILOC
                    GROUP BY itemno
                ) stock ON ai.itemno = stock.itemno
                
                LEFT JOIN customer_history ch ON ai.itemno = ch.itemno
                
                WHERE ai.vector_desc IS NOT NULL
                AND ai."DESC" IS NOT NULL
                AND LENGTH(TRIM(ai."DESC")) > 0
                AND (
                    (UPPER(ai."DESC") LIKE '%' || UPPER(v_search_term) || '%') OR
                    (ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE '%' || UPPER(v_search_term) || '%') OR
                    ((1 - vector_distance(ai.vector_desc, v_query_vector, COSINE)) >= 0.3) OR
                    (ch.itemno IS NOT NULL)
                )
            )
            SELECT
                itemno,
                "DESC",
                SYNONYMS,
                brand_name,
                
                -- Weighted total score
                (
                    text_match_score * 1.5 +     -- Highest: text matching
                    history_score * 1.8 +        -- Highest: customer history  
                    brand_score * 1.2 +          -- High: BALAR brand
                    stock_score * 1.0 +          -- Medium: stock
                    similarity_score * 0.8       -- Lower: vector similarity
                ) AS total_score,
                
                text_match_score,
                brand_score,
                history_score,
                stock_score,
                ROUND(similarity_score, 1) as similarity_score,
                stock_qty,
                customer_orders,
                last_purchase,
                
                -- Recommendation type
                CASE 
                    WHEN customer_orders > 0 THEN 'REPURCHASE'
                    WHEN brand_score = 100 THEN 'BALAR_BRAND'
                    WHEN text_match_score >= 80 THEN 'EXACT_MATCH'
                    ELSE 'SIMILARITY'
                END AS rec_type
                
            FROM scored_items
            WHERE (text_match_score + history_score + similarity_score) > 20
            ORDER BY
                total_score DESC,
                history_score DESC,
                brand_score DESC,
                text_match_score DESC,
                stock_qty DESC,
                itemno ASC
            OFFSET v_offset ROWS
            FETCH NEXT v_top_n ROWS ONLY
        ) LOOP
            v_count := v_count + 1;
            
            -- Display: Item Number | Description | Quantity
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

    -- Summary
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SUMMARY ===');
    DBMS_OUTPUT.PUT_LINE('Results Found: ' || v_count);
    
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('No results found. Try different search terms.');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('System Error: ' || SQLERRM);
END;
/