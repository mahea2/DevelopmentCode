-- Effective Hybrid Search - Simplified and Practical
-- Focus on what actually works for product search

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
    v_search_words      VARCHAR2(200);

BEGIN
    -- Input validation
    IF v_search_term IS NULL OR LENGTH(TRIM(v_search_term)) = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Search term cannot be empty.');
        RETURN;
    END IF;

    -- Setup
    v_offset := (v_page_number - 1) * v_top_n;
    v_search_term := UPPER(TRIM(v_search_term));
    
    -- Extract individual words for better matching
    v_search_words := REPLACE(v_search_term, ' ', '|');

    DBMS_OUTPUT.PUT_LINE('=== EFFECTIVE HYBRID SEARCH ===');
    DBMS_OUTPUT.PUT_LINE('Search Term: "' || v_search_term || '"');
    DBMS_OUTPUT.PUT_LINE('Customer: ' || v_customer_id);
    DBMS_OUTPUT.PUT_LINE('');

    -- Generate vector embedding
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
            DBMS_OUTPUT.PUT_LINE('⚠ Vector generation failed, using text search only');
            v_query_vector := NULL;
    END;

    -- Execute effective search
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SEARCH RESULTS ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('ITEM NUMBER', 15) || ' | ' || RPAD('DESCRIPTION', 50) || ' | ' || LPAD('QUANTITY', 10));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 15, '-') || ' | ' || RPAD('-', 50, '-') || ' | ' || RPAD('-', 10, '-'));
    
    BEGIN
        -- Simplified but effective search
        FOR rec IN (
            WITH customer_history AS (
                -- Simple customer history
                SELECT 
                    d.item,
                    COUNT(*) as purchase_count,
                    MAX(TO_DATE(TO_CHAR(h.invdate), 'YYYYMMDD')) as last_purchase,
                    SUM(d.qtyshipped) as total_qty_bought
                FROM SFLDAT.OEINVH h
                INNER JOIN SFLDAT.OEINVD d ON h.invuniq = d.invuniq
                WHERE h.customer = v_customer_id
                AND TO_DATE(TO_CHAR(h.invdate), 'YYYYMMDD') >= SYSDATE - v_days_lookback
                AND d.qtyshipped > 0
                GROUP BY d.item
            )
            SELECT 
                ai.itemno,
                ai."DESC",
                ai.SYNONYMS,
                
                -- Simple but effective scoring
                (
                    -- Text matching score (most important)
                    CASE
                        WHEN UPPER(ai."DESC") LIKE '%' || v_search_term || '%' THEN 100
                        WHEN ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE '%' || v_search_term || '%' THEN 90
                        -- Individual word matching
                        WHEN REGEXP_LIKE(UPPER(ai."DESC"), v_search_words) THEN 70
                        WHEN ai.SYNONYMS IS NOT NULL AND REGEXP_LIKE(UPPER(ai.SYNONYMS), v_search_words) THEN 60
                        -- Partial matching
                        WHEN INSTR(UPPER(ai."DESC"), SUBSTR(v_search_term, 1, 4)) > 0 THEN 40
                        ELSE 0
                    END
                    +
                    -- Customer history boost (important)
                    CASE WHEN ch.item IS NOT NULL THEN 50 ELSE 0 END
                    +
                    -- BALAR brand boost
                    CASE WHEN UPPER(NVL(brand.value, '')) IN ('BALAR', 'BALARS') THEN 30 ELSE 0 END
                    +
                    -- Stock availability boost
                    CASE 
                        WHEN stock.total_qty > 0 THEN 20 
                        ELSE -10 
                    END
                    +
                    -- Vector similarity boost (if available)
                    CASE 
                        WHEN v_query_vector IS NOT NULL AND ai.vector_desc IS NOT NULL THEN
                            GREATEST(0, (1 - vector_distance(ai.vector_desc, v_query_vector, COSINE)) * 30)
                        ELSE 0
                    END
                ) AS total_score,
                
                -- Display information
                COALESCE(stock.total_qty, 0) AS stock_qty,
                COALESCE(brand.value, '') AS brand_name,
                COALESCE(ch.purchase_count, 0) AS bought_before,
                COALESCE(ch.last_purchase, TO_DATE('1900-01-01', 'YYYY-MM-DD')) AS last_bought,
                
                -- Match type for user understanding
                CASE
                    WHEN UPPER(ai."DESC") LIKE '%' || v_search_term || '%' THEN 'EXACT_MATCH'
                    WHEN ch.item IS NOT NULL THEN 'PURCHASED_BEFORE'
                    WHEN UPPER(NVL(brand.value, '')) IN ('BALAR', 'BALARS') THEN 'BALAR_BRAND'
                    WHEN REGEXP_LIKE(UPPER(ai."DESC"), v_search_words) THEN 'PARTIAL_MATCH'
                    ELSE 'SIMILAR'
                END AS match_type
                
            FROM AI_ICITEM ai
            
            -- Simple joins
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
            
            LEFT JOIN customer_history ch ON ai.itemno = ch.item
            
            WHERE ai."DESC" IS NOT NULL
            AND (
                -- Must match at least one of these conditions
                UPPER(ai."DESC") LIKE '%' || v_search_term || '%' OR
                (ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE '%' || v_search_term || '%') OR
                REGEXP_LIKE(UPPER(ai."DESC"), v_search_words) OR
                (ai.SYNONYMS IS NOT NULL AND REGEXP_LIKE(UPPER(ai.SYNONYMS), v_search_words)) OR
                ch.item IS NOT NULL OR
                (v_query_vector IS NOT NULL AND ai.vector_desc IS NOT NULL AND 
                 (1 - vector_distance(ai.vector_desc, v_query_vector, COSINE)) > 0.5)
            )
            
            ORDER BY 
                total_score DESC,
                bought_before DESC,
                stock_qty DESC,
                itemno ASC
            
            OFFSET v_offset ROWS
            FETCH NEXT v_top_n ROWS ONLY
        ) LOOP
            v_count := v_count + 1;
            
            -- Clean output format
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

    -- Summary with insights
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SUMMARY ===');
    DBMS_OUTPUT.PUT_LINE('Results Found: ' || v_count);
    
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('No results found. Try:');
        DBMS_OUTPUT.PUT_LINE('• Simpler search terms (e.g., "ice" instead of "ice cubes")');
        DBMS_OUTPUT.PUT_LINE('• Check spelling');
        DBMS_OUTPUT.PUT_LINE('• Use broader categories');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Tips: Results prioritize exact matches, your purchase history,');
        DBMS_OUTPUT.PUT_LINE('      BALAR brand items, and available stock.');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('System Error: ' || SQLERRM);
END;
/