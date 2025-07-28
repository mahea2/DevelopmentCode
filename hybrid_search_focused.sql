-- Focused Hybrid Search with Customer History Logic
-- Exact Requirements:
-- 1. Match DESC or SYNONYMS in AI_ICITEM
-- 2. Prioritize BALAR brand from ICITEMO with QTYONHAND from ICILOC
-- 3. Use OEINVH and OEINVD for customer purchase history recommendations

SET SERVEROUTPUT ON;

DECLARE
    -- --- Configuration ---
    v_search_term       VARCHAR2(100) := 'ice cubes';     -- Search term to match
    v_customer_id       VARCHAR2(20)  := 'CUST001';       -- Customer ID for history
    v_top_n             INTEGER       := 10;              -- Number of results
    v_page_number       INTEGER       := 1;               -- Page number
    v_days_lookback     INTEGER       := 365;             -- Days for customer history
    -- -------------------

    v_query_vector      VECTOR;
    v_count             INTEGER       := 0;
    v_offset            INTEGER;
    v_search_upper      VARCHAR2(100);

    -- Focused cursor following exact logic requirements
    CURSOR c_focused_search(
        p_vector VECTOR,
        p_search_term VARCHAR2,
        p_customer_id VARCHAR2,
        p_days_back INTEGER,
        p_offset INTEGER,
        p_limit INTEGER
    ) IS
        WITH customer_purchase_history AS (
            -- Get customer's purchase history from OEINVH and OEINVD
            SELECT 
                d.itemno,
                COUNT(DISTINCT h.invno) as order_count,
                SUM(d.qtyshipped) as total_qty_purchased,
                MAX(h.invdate) as last_purchase_date,
                SUM(d.amount) as total_amount_spent,
                AVG(d.amount) as avg_order_amount,
                -- Calculate customer affinity score
                CASE 
                    WHEN MAX(h.invdate) >= SYSDATE - 30 THEN 50   -- Recent purchase (last 30 days)
                    WHEN MAX(h.invdate) >= SYSDATE - 90 THEN 40   -- Recent purchase (last 90 days)
                    WHEN MAX(h.invdate) >= SYSDATE - 180 THEN 30  -- Medium recent (last 6 months)
                    WHEN MAX(h.invdate) >= SYSDATE - 365 THEN 20  -- Within last year
                    ELSE 10                                        -- Older purchases
                END +
                CASE 
                    WHEN COUNT(DISTINCT h.invno) >= 5 THEN 30     -- Frequent buyer
                    WHEN COUNT(DISTINCT h.invno) >= 3 THEN 20     -- Regular buyer
                    WHEN COUNT(DISTINCT h.invno) >= 2 THEN 10     -- Occasional buyer
                    ELSE 5                                         -- Single purchase
                END as customer_affinity_score
            FROM SFLDAT.OEINVH h
            INNER JOIN SFLDAT.OEINVD d ON h.invno = d.invno
            WHERE h.custno = p_customer_id
            AND h.invdate >= SYSDATE - p_days_back
            AND d.qtyshipped > 0
            AND d.amount > 0
            GROUP BY d.itemno
        ),
        similar_customers_items AS (
            -- Find items purchased by customers with similar buying patterns
            SELECT DISTINCT 
                d2.itemno,
                COUNT(DISTINCT h2.custno) as customer_count
            FROM SFLDAT.OEINVH h1
            INNER JOIN SFLDAT.OEINVD d1 ON h1.invno = d1.invno
            INNER JOIN SFLDAT.OEINVD d2 ON d1.itemno = d2.itemno
            INNER JOIN SFLDAT.OEINVH h2 ON d2.invno = h2.invno
            WHERE h1.custno = p_customer_id
            AND h1.invdate >= SYSDATE - (p_days_back/2)
            AND h2.custno != p_customer_id
            AND h2.invdate >= SYSDATE - p_days_back
            AND d2.qtyshipped > 0
            GROUP BY d2.itemno
            HAVING COUNT(DISTINCT h2.custno) >= 2  -- At least 2 other customers bought this
        ),
        scored_items AS (
            SELECT
                ai.itemno,
                ai."DESC",
                ai.SYNONYMS,
                
                -- Step 1: Vector similarity score
                vector_distance(ai.vector_desc, p_vector, COSINE) AS distance,
                (1 - vector_distance(ai.vector_desc, p_vector, COSINE)) * 100 AS vector_similarity,
                
                -- Step 1: Text matching score (DESC and SYNONYMS)
                CASE
                    -- Exact match in description
                    WHEN UPPER(ai."DESC") = UPPER(p_search_term) THEN 100
                    -- Starts with search term
                    WHEN UPPER(ai."DESC") LIKE UPPER(p_search_term) || '%' THEN 90
                    -- Contains search term
                    WHEN UPPER(ai."DESC") LIKE '%' || UPPER(p_search_term) || '%' THEN 80
                    -- Exact match in synonyms
                    WHEN ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) = UPPER(p_search_term) THEN 95
                    -- Synonyms contains search term
                    WHEN ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE '%' || UPPER(p_search_term) || '%' THEN 75
                    -- Word boundary matches
                    WHEN REGEXP_LIKE(UPPER(ai."DESC"), '\b' || UPPER(p_search_term) || '\b') THEN 70
                    WHEN ai.SYNONYMS IS NOT NULL AND REGEXP_LIKE(UPPER(ai.SYNONYMS), '\b' || UPPER(p_search_term) || '\b') THEN 65
                    ELSE 0
                END AS text_match_score,
                
                -- Step 2: BALAR brand prioritization
                CASE
                    WHEN UPPER(brand.value) = 'BALAR' THEN 100
                    WHEN UPPER(brand.value) = 'BALARS' THEN 100  -- Handle variations
                    WHEN brand.value IS NOT NULL THEN 20
                    ELSE 0
                END AS brand_priority_score,
                
                -- Step 2: Stock availability from ICILOC
                CASE 
                    WHEN stock.total_qty > 100 THEN 50
                    WHEN stock.total_qty > 50 THEN 40
                    WHEN stock.total_qty > 25 THEN 30
                    WHEN stock.total_qty > 10 THEN 20
                    WHEN stock.total_qty > 0 THEN 10
                    ELSE -20  -- Penalty for out of stock
                END AS stock_availability_score,
                
                -- Step 3: Customer purchase history score
                COALESCE(cph.customer_affinity_score, 0) AS customer_history_score,
                
                -- Step 3: Collaborative filtering score
                CASE 
                    WHEN sci.itemno IS NOT NULL THEN 
                        LEAST(sci.customer_count * 5, 25)  -- Cap at 25 points
                    ELSE 0
                END AS collaborative_score,
                
                -- Include raw data for display
                COALESCE(stock.total_qty, 0) AS stock_qty,
                COALESCE(brand.value, 'Unknown') AS brand_name,
                COALESCE(cph.order_count, 0) AS customer_orders,
                COALESCE(cph.last_purchase_date, TO_DATE('1900-01-01', 'YYYY-MM-DD')) AS last_purchase,
                COALESCE(cph.total_amount_spent, 0) AS customer_spent,
                COALESCE(sci.customer_count, 0) AS similar_customers
                
            FROM AI_ICITEM ai
            
            -- Step 2: Join brand information
            LEFT JOIN (
                SELECT itemno, value
                FROM SFLDAT.ICITEMO 
                WHERE optfield = 'BRAND'
            ) brand ON ai.itemno = brand.itemno
            
            -- Step 2: Join stock information
            LEFT JOIN (
                SELECT itemno, SUM(GREATEST(QTYONHAND, 0)) as total_qty
                FROM SFLDAT.ICILOC
                GROUP BY itemno
            ) stock ON ai.itemno = stock.itemno
            
            -- Step 3: Join customer history
            LEFT JOIN customer_purchase_history cph ON ai.itemno = cph.itemno
            
            -- Step 3: Join collaborative filtering
            LEFT JOIN similar_customers_items sci ON ai.itemno = sci.itemno
            
            WHERE ai.vector_desc IS NOT NULL
            AND ai."DESC" IS NOT NULL
            AND LENGTH(TRIM(ai."DESC")) > 0
            -- Filter: Must have text match OR vector similarity OR customer history
            AND (
                (UPPER(ai."DESC") LIKE '%' || UPPER(p_search_term) || '%') OR
                (ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE '%' || UPPER(p_search_term) || '%') OR
                ((1 - vector_distance(ai.vector_desc, p_vector, COSINE)) >= 0.3) OR
                (cph.itemno IS NOT NULL)
            )
        )
        SELECT
            itemno,
            "DESC",
            SYNONYMS,
            brand_name,
            
            -- Calculate weighted total score with clear priorities
            (
                text_match_score * 1.5 +           -- Highest priority: text matching
                brand_priority_score * 1.2 +       -- High priority: BALAR brand
                customer_history_score * 1.8 +     -- Highest priority: customer history
                stock_availability_score * 1.0 +   -- Medium priority: stock
                vector_similarity * 0.8 +          -- Lower priority: vector similarity
                collaborative_score * 0.6          -- Lower priority: collaborative
            ) AS total_score,
            
            -- Individual scores for transparency
            text_match_score,
            brand_priority_score,
            customer_history_score,
            stock_availability_score,
            ROUND(vector_similarity, 1) as vector_similarity,
            collaborative_score,
            
            -- Display data
            stock_qty,
            customer_orders,
            last_purchase,
            customer_spent,
            similar_customers,
            
            -- Recommendation reasoning
            CASE 
                WHEN customer_orders > 0 THEN 'REPURCHASE_RECOMMENDATION'
                WHEN similar_customers > 0 THEN 'COLLABORATIVE_RECOMMENDATION'
                WHEN brand_priority_score = 100 THEN 'BALAR_BRAND_MATCH'
                WHEN text_match_score >= 80 THEN 'EXACT_SEARCH_MATCH'
                WHEN text_match_score >= 65 THEN 'PARTIAL_SEARCH_MATCH'
                ELSE 'SIMILARITY_MATCH'
            END AS recommendation_type
            
        FROM scored_items
        WHERE (text_match_score + customer_history_score + vector_similarity) > 20
        ORDER BY
            total_score DESC,
            customer_history_score DESC,  -- Prioritize customer history
            brand_priority_score DESC,    -- Then BALAR brand
            text_match_score DESC,        -- Then text matching
            stock_qty DESC,               -- Then stock availability
            itemno ASC
        OFFSET p_offset ROWS
        FETCH NEXT p_limit ROWS ONLY;

    rec c_focused_search%ROWTYPE;

BEGIN
    -- Input validation
    IF v_search_term IS NULL OR LENGTH(TRIM(v_search_term)) = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Search term cannot be empty.');
        RETURN;
    END IF;

    -- Prepare parameters
    v_search_upper := UPPER(TRIM(v_search_term));
    v_offset := (v_page_number - 1) * v_top_n;

    DBMS_OUTPUT.PUT_LINE('=== FOCUSED HYBRID SEARCH ===');
    DBMS_OUTPUT.PUT_LINE('Search Term: "' || v_search_term || '"');
    DBMS_OUTPUT.PUT_LINE('Customer: ' || v_customer_id);
    DBMS_OUTPUT.PUT_LINE('History Period: ' || v_days_lookback || ' days');
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
        DBMS_OUTPUT.PUT_LINE('✓ Vector embedding generated');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('✗ Vector generation failed: ' || SQLERRM);
            RETURN;
    END;

    -- Execute focused search
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SEARCH RESULTS ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('ITEM NUMBER', 15) || ' | ' || RPAD('DESCRIPTION', 50) || ' | ' || LPAD('QUANTITY', 10));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 15, '-') || ' | ' || RPAD('-', 50, '-') || ' | ' || RPAD('-', 10, '-'));
    
    BEGIN
        OPEN c_focused_search(
            v_query_vector, v_search_term, v_customer_id, 
            v_days_lookback, v_offset, v_top_n
        );
        
        LOOP
            FETCH c_focused_search INTO rec;
            EXIT WHEN c_focused_search%NOTFOUND;

            v_count := v_count + 1;
            
            -- Display: Item Number | Description | Quantity
            DBMS_OUTPUT.PUT_LINE(
                RPAD(rec.itemno, 15) || ' | ' ||
                RPAD(SUBSTR(rec."DESC", 1, 50), 50) || ' | ' ||
                LPAD('QTY: ' || rec.stock_qty, 10)
            );
            
        END LOOP;
        CLOSE c_focused_search;
        
    EXCEPTION
        WHEN OTHERS THEN
            IF c_focused_search%ISOPEN THEN
                CLOSE c_focused_search;
            END IF;
            DBMS_OUTPUT.PUT_LINE('✗ Search error: ' || SQLERRM);
            RETURN;
    END;

    -- Results summary
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== SUMMARY ===');
    DBMS_OUTPUT.PUT_LINE('Results Found: ' || v_count);
    
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('No results found. Check:');
        DBMS_OUTPUT.PUT_LINE('• Search term matches item descriptions');
        DBMS_OUTPUT.PUT_LINE('• Customer ID exists in order history');
        DBMS_OUTPUT.PUT_LINE('• Items have vector embeddings');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        IF c_focused_search%ISOPEN THEN
            CLOSE c_focused_search;
        END IF;
        DBMS_OUTPUT.PUT_LINE('System Error: ' || SQLERRM);
END;
/