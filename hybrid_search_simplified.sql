-- Simplified Productive Hybrid Search - Error-Safe Version
-- Handles missing tables gracefully and provides core functionality

SET SERVEROUTPUT ON;

DECLARE
    -- --- Configuration ---
    v_search_term       VARCHAR2(100) := 'ice cubes';     -- Search term
    v_customer_id       VARCHAR2(20)  := 'CUST001';       -- Customer ID for personalized results
    v_top_n             INTEGER       := 10;              -- Results per page
    v_page_number       INTEGER       := 1;               -- Page number
    v_include_history   VARCHAR2(1)   := 'Y';             -- Include purchase history ('Y'/'N')
    v_days_lookback     INTEGER       := 365;             -- Days to look back for purchase history
    v_min_similarity    NUMBER        := 0.1;             -- Minimum similarity threshold
    -- -------------------

    v_query_vector      VECTOR;
    v_count             INTEGER       := 0;
    v_search_term_regex VARCHAR2(200);
    v_offset            INTEGER;
    v_customer_exists   INTEGER       := 0;
    v_history_weight    NUMBER        := 1.0;
    v_table_exists      INTEGER       := 0;

    -- Check if table exists
    FUNCTION table_exists(p_table_name VARCHAR2, p_owner VARCHAR2 DEFAULT USER) RETURN BOOLEAN IS
        v_count INTEGER := 0;
    BEGIN
        SELECT COUNT(*)
        INTO v_count
        FROM all_tables
        WHERE table_name = UPPER(p_table_name)
        AND owner = UPPER(p_owner);
        
        RETURN v_count > 0;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN FALSE;
    END;

    -- Simplified cursor that works with available tables
    CURSOR c_safe_search(
        p_vector VECTOR, 
        p_regex VARCHAR2, 
        p_offset INTEGER, 
        p_limit INTEGER,
        p_customer_id VARCHAR2,
        p_days_back INTEGER,
        p_min_sim NUMBER
    ) IS
        WITH customer_history AS (
            -- Only include customer history if OEIVH table exists
            SELECT 
                h.itemno,
                COUNT(*) as purchase_frequency,
                MAX(h.invdate) as last_purchase_date,
                SUM(h.amount) as total_spent,
                -- Recency score
                CASE 
                    WHEN MAX(h.invdate) >= SYSDATE - 30 THEN 30
                    WHEN MAX(h.invdate) >= SYSDATE - 90 THEN 20
                    WHEN MAX(h.invdate) >= SYSDATE - 180 THEN 15
                    WHEN MAX(h.invdate) >= SYSDATE - 365 THEN 10
                    ELSE 5
                END as recency_score,
                -- Frequency score
                CASE 
                    WHEN COUNT(*) >= 10 THEN 25
                    WHEN COUNT(*) >= 5 THEN 20
                    WHEN COUNT(*) >= 3 THEN 15
                    WHEN COUNT(*) >= 2 THEN 10
                    ELSE 5
                END as frequency_score
            FROM SFLDAT.OEIVH h
            WHERE h.custno = p_customer_id
            AND h.invdate >= SYSDATE - p_days_back
            AND h.amount > 0
            AND v_table_exists = 1  -- Only execute if table exists
            GROUP BY h.itemno
            UNION ALL
            -- Dummy row to prevent empty result set
            SELECT NULL, 0, NULL, 0, 0, 0 FROM dual WHERE v_table_exists = 0
        ),
        scored_items AS (
            SELECT
                ai.itemno,
                ai."DESC",
                ai.SYNONYMS,
                
                -- Core similarity calculations
                vector_distance(ai.vector_desc, p_vector, COSINE) AS distance,
                (1 - vector_distance(ai.vector_desc, p_vector, COSINE)) * 100 AS similarity_score,
                
                -- Stock scoring with safe join
                CASE 
                    WHEN loc.total_qty > 100 THEN 40
                    WHEN loc.total_qty > 50 THEN 35
                    WHEN loc.total_qty > 10 THEN 30
                    WHEN loc.total_qty > 0 THEN 20
                    ELSE 0
                END AS stock_score,
                
                -- Enhanced keyword matching
                CASE
                    WHEN UPPER(ai."DESC") = UPPER(v_search_term) THEN 60
                    WHEN UPPER(ai."DESC") LIKE UPPER(v_search_term) || '%' THEN 50
                    WHEN UPPER(ai."DESC") LIKE '%' || UPPER(v_search_term) || '%' THEN 40
                    WHEN ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE '%' || UPPER(v_search_term) || '%' THEN 35
                    WHEN REGEXP_LIKE(UPPER(ai."DESC"), p_regex, 'i') THEN 25
                    WHEN ai.SYNONYMS IS NOT NULL AND REGEXP_LIKE(UPPER(ai.SYNONYMS), p_regex, 'i') THEN 20
                    ELSE 0
                END AS keyword_score,
                
                -- Brand scoring (safe)
                CASE
                    WHEN UPPER(NVL(opt.value, '')) = 'BALARS' THEN 25
                    WHEN opt.value IS NOT NULL THEN 10
                    ELSE 0
                END AS brand_score,
                
                -- Customer history scoring (safe)
                CASE 
                    WHEN ch.itemno IS NOT NULL AND ch.itemno = ai.itemno THEN 
                        (ch.recency_score + ch.frequency_score) * v_history_weight
                    ELSE 0
                END AS history_score,
                
                -- Include metrics
                COALESCE(loc.total_qty, 0) AS stock_qty,
                COALESCE(ch.purchase_frequency, 0) AS cust_purchase_freq,
                COALESCE(ch.last_purchase_date, TO_DATE('1900-01-01', 'YYYY-MM-DD')) AS last_purchase,
                COALESCE(ch.total_spent, 0) AS cust_total_spent
                
            FROM AI_ICITEM ai
            
            -- Safe left joins
            LEFT JOIN (
                SELECT itemno, value
                FROM SFLDAT.ICITEMO 
                WHERE optfield = 'BRAND'
            ) opt ON ai.itemno = opt.itemno
            
            LEFT JOIN (
                SELECT itemno, SUM(GREATEST(QTYONHAND, 0)) as total_qty
                FROM sfldat.iciloc
                GROUP BY itemno
            ) loc ON ai.itemno = loc.itemno
            
            LEFT JOIN customer_history ch ON ai.itemno = ch.itemno
            
            WHERE ai.vector_desc IS NOT NULL
            AND ai."DESC" IS NOT NULL
            AND LENGTH(TRIM(ai."DESC")) > 0
            AND (1 - vector_distance(ai.vector_desc, p_vector, COSINE)) >= p_min_sim
        )
        SELECT
            itemno,
            "DESC",
            SYNONYMS,
            
            -- Balanced total score
            (similarity_score * 1.0 +
             stock_score * 0.8 +
             keyword_score * 1.2 +
             brand_score * 0.6 +
             history_score * 1.5
            ) AS total_score,
            
            similarity_score,
            keyword_score,
            stock_score,
            brand_score,
            history_score,
            distance,
            stock_qty,
            cust_purchase_freq,
            last_purchase,
            cust_total_spent,
            
            -- Recommendation type
            CASE 
                WHEN history_score > 0 THEN 'REPURCHASE'
                WHEN keyword_score > 40 THEN 'SEARCH_MATCH'
                ELSE 'SIMILARITY_MATCH'
            END AS recommendation_type
            
        FROM scored_items
        WHERE (similarity_score + keyword_score + history_score) > 10
        ORDER BY
            total_score DESC,
            similarity_score DESC,
            stock_qty DESC,
            itemno ASC
        OFFSET p_offset ROWS
        FETCH NEXT p_limit ROWS ONLY;

    rec c_safe_search%ROWTYPE;

BEGIN
    -- Step 1: Input validation
    IF v_search_term IS NULL OR LENGTH(TRIM(v_search_term)) = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Search term cannot be empty.');
        RETURN;
    END IF;
    
    IF v_top_n <= 0 OR v_page_number <= 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Page number and results per page must be positive integers.');
        RETURN;
    END IF;

    -- Step 2: Check table availability
    DBMS_OUTPUT.PUT_LINE('=== CHECKING SYSTEM AVAILABILITY ===');
    
    IF table_exists('AI_ICITEM') THEN
        DBMS_OUTPUT.PUT_LINE('✓ AI_ICITEM table found');
    ELSE
        DBMS_OUTPUT.PUT_LINE('✗ AI_ICITEM table not found - cannot proceed');
        RETURN;
    END IF;
    
    IF table_exists('OEIVH', 'SFLDAT') THEN
        DBMS_OUTPUT.PUT_LINE('✓ SFLDAT.OEIVH table found - customer history enabled');
        v_table_exists := 1;
    ELSE
        DBMS_OUTPUT.PUT_LINE('⚠ SFLDAT.OEIVH table not found - using generic search');
        v_table_exists := 0;
        v_history_weight := 0.0;
    END IF;
    
    IF table_exists('ICITEMO', 'SFLDAT') THEN
        DBMS_OUTPUT.PUT_LINE('✓ SFLDAT.ICITEMO table found - brand scoring enabled');
    ELSE
        DBMS_OUTPUT.PUT_LINE('⚠ SFLDAT.ICITEMO table not found - brand scoring disabled');
    END IF;
    
    IF table_exists('ICILOC', 'SFLDAT') THEN
        DBMS_OUTPUT.PUT_LINE('✓ SFLDAT.ICILOC table found - stock info enabled');
    ELSE
        DBMS_OUTPUT.PUT_LINE('⚠ SFLDAT.ICILOC table not found - stock info disabled');
    END IF;

    -- Step 3: Customer validation (if history table exists)
    IF v_table_exists = 1 AND v_include_history = 'Y' AND v_customer_id IS NOT NULL THEN
        BEGIN
            SELECT COUNT(DISTINCT custno) 
            INTO v_customer_exists 
            FROM SFLDAT.OEIVH 
            WHERE custno = v_customer_id 
            AND invdate >= SYSDATE - v_days_lookback;
            
            IF v_customer_exists = 0 THEN
                DBMS_OUTPUT.PUT_LINE('⚠ No purchase history found for customer ' || v_customer_id);
                v_history_weight := 0.0;
            ELSE
                DBMS_OUTPUT.PUT_LINE('✓ Found purchase history for customer ' || v_customer_id);
                v_history_weight := 1.0;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('⚠ Could not access customer history');
                v_history_weight := 0.0;
        END;
    END IF;

    -- Step 4: Prepare search parameters
    v_search_term := TRIM(v_search_term);
    v_search_term_regex := '\b' || REGEXP_REPLACE(UPPER(v_search_term), '([.*+?^${}()|[\]\\])', '\\\1') || '\b';
    v_offset := (v_page_number - 1) * v_top_n;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SEARCH CONFIGURATION ===');
    DBMS_OUTPUT.PUT_LINE('Search Term: "' || v_search_term || '"');
    DBMS_OUTPUT.PUT_LINE('Customer ID: ' || COALESCE(v_customer_id, 'Generic Search'));
    DBMS_OUTPUT.PUT_LINE('History Weight: ' || v_history_weight);
    DBMS_OUTPUT.PUT_LINE('Min Similarity: ' || v_min_similarity);

    -- Step 5: Generate embedding vector
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
        DBMS_OUTPUT.PUT_LINE('✓ Vector embedding generated successfully');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('✗ Error generating vector: ' || SQLERRM);
            RETURN;
    END;

    -- Step 6: Execute search
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SEARCH RESULTS (Page ' || v_page_number || ') ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('ITEM NUMBER', 15) || ' | ' || RPAD('DESCRIPTION', 50) || ' | ' || LPAD('QUANTITY', 10));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 15, '-') || ' | ' || RPAD('-', 50, '-') || ' | ' || RPAD('-', 10, '-'));
    
    BEGIN
        OPEN c_safe_search(
            v_query_vector, v_search_term_regex, v_offset, v_top_n,
            v_customer_id, v_days_lookback, v_min_similarity
        );
        
        LOOP
            FETCH c_safe_search INTO rec;
            EXIT WHEN c_safe_search%NOTFOUND;

            v_count := v_count + 1;
            
            -- Simple result display: Item Number, Description, Quantity
            DBMS_OUTPUT.PUT_LINE(
                RPAD(rec.itemno, 15) || ' | ' ||
                RPAD(SUBSTR(rec."DESC", 1, 50), 50) || ' | ' ||
                LPAD('QTY: ' || rec.stock_qty, 10)
            );
        END LOOP;
        CLOSE c_safe_search;
        
    EXCEPTION
        WHEN OTHERS THEN
            IF c_safe_search%ISOPEN THEN
                CLOSE c_safe_search;
            END IF;
            DBMS_OUTPUT.PUT_LINE('✗ Search execution error: ' || SQLERRM);
            RETURN;
    END;

    -- Step 7: Results summary
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SUMMARY ===');
    DBMS_OUTPUT.PUT_LINE('Results Found: ' || v_count);
    
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('No results found. Suggestions:');
        DBMS_OUTPUT.PUT_LINE('• Try different search terms');
        DBMS_OUTPUT.PUT_LINE('• Lower similarity threshold');
        DBMS_OUTPUT.PUT_LINE('• Check if items have vector embeddings');
        DBMS_OUTPUT.PUT_LINE('• Verify table permissions');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Search completed successfully.');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        IF c_safe_search%ISOPEN THEN
            CLOSE c_safe_search;
        END IF;
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('=== SYSTEM ERROR ===');
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Line: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/