-- Optimized Hybrid Search Block - FIXED VERSION
-- Key Fixes Applied:
-- 1. Fixed REGEXP pattern to properly handle word boundaries
-- 2. Corrected vector similarity calculation (lower distance = higher similarity)
-- 3. Added proper NULL handling and data validation
-- 4. Improved scoring algorithm balance
-- 5. Enhanced error handling and debugging output
-- 6. Fixed cursor variable binding issues

SET SERVEROUTPUT ON;

DECLARE
    -- --- Configuration ---
    v_search_term       VARCHAR2(100) := 'ice cubes'; -- The word or phrase to search for.
    v_top_n             INTEGER       := 5;       -- The number of results to return per page.
    v_page_number       INTEGER       := 1;       -- The page of results to fetch.
    -- -------------------

    v_query_vector      VECTOR;
    v_count             INTEGER       := 0;
    v_search_term_regex VARCHAR2(200);
    v_offset            INTEGER;
    v_total_items       INTEGER       := 0;

    -- Explicit cursor with proper variable binding
    CURSOR c_hybrid_search(p_vector VECTOR, p_regex VARCHAR2, p_offset INTEGER, p_limit INTEGER) IS
        WITH scored_items AS (
            SELECT
                ai.itemno,
                ai."DESC",
                ai.SYNONYMS,
                -- Fixed: Convert distance to similarity score (lower distance = higher similarity)
                vector_distance(ai.vector_desc, p_vector, COSINE) AS distance,
                (1 - vector_distance(ai.vector_desc, p_vector, COSINE)) * 100 AS similarity_score,
                
                -- Stock availability bonus
                CASE 
                    WHEN COALESCE(loc.total_qty, 0) > 0 THEN 50 
                    ELSE 0 
                END AS stock_score,
                
                -- Keyword matching scores with improved logic
                CASE
                    WHEN UPPER(ai."DESC") LIKE '%' || UPPER(v_search_term) || '%' THEN 40
                    WHEN ai.SYNONYMS IS NOT NULL AND UPPER(ai.SYNONYMS) LIKE '%' || UPPER(v_search_term) || '%' THEN 30
                    WHEN REGEXP_LIKE(UPPER(ai."DESC"), p_regex, 'i') THEN 25
                    WHEN ai.SYNONYMS IS NOT NULL AND REGEXP_LIKE(UPPER(ai.SYNONYMS), p_regex, 'i') THEN 20
                    ELSE 0
                END AS keyword_score,
                
                -- Brand preference scoring
                CASE
                    WHEN UPPER(opt.value) = 'BALARS' THEN 15
                    WHEN opt.value IS NOT NULL THEN 5
                    ELSE 0
                END AS brand_score,
                
                -- Include stock quantity for debugging
                COALESCE(loc.total_qty, 0) AS stock_qty
            FROM
                AI_ICITEM ai
            LEFT JOIN SFLDAT.ICITEMO opt ON ai.itemno = opt.itemno AND opt.optfield = 'BRAND'
            LEFT JOIN (
                SELECT itemno, SUM(QTYONHAND) as total_qty
                FROM sfldat.iciloc
                WHERE QTYONHAND > 0  -- Only consider positive quantities
                GROUP BY itemno
            ) loc ON ai.itemno = loc.itemno
            WHERE
                ai.vector_desc IS NOT NULL
                AND ai."DESC" IS NOT NULL
                AND LENGTH(TRIM(ai."DESC")) > 0
        )
        SELECT
            itemno,
            "DESC",
            SYNONYMS,
            -- Balanced total score calculation
            (similarity_score + stock_score + keyword_score + brand_score) AS total_score,
            similarity_score,
            keyword_score,
            stock_score,
            brand_score,
            distance,
            stock_qty
        FROM scored_items
        ORDER BY
            total_score DESC,
            similarity_score DESC,
            itemno ASC  -- Consistent ordering for pagination
        OFFSET p_offset ROWS
        FETCH NEXT p_limit ROWS ONLY;

    rec c_hybrid_search%ROWTYPE;

BEGIN
    -- Step 1: Validate input parameters
    IF v_search_term IS NULL OR LENGTH(TRIM(v_search_term)) = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Search term cannot be empty.');
        RETURN;
    END IF;
    
    IF v_top_n <= 0 OR v_page_number <= 0 THEN
        DBMS_OUTPUT.PUT_LINE('Error: Page number and results per page must be positive integers.');
        RETURN;
    END IF;

    -- Step 2: Prepare REGEXP pattern with proper escaping
    v_search_term := TRIM(v_search_term);
    -- Escape special regex characters and create word boundary pattern
    v_search_term_regex := '\b' || REGEXP_REPLACE(UPPER(v_search_term), '([.*+?^${}()|[\]\\])', '\\\1') || '\b';
    v_offset := (v_page_number - 1) * v_top_n;

    DBMS_OUTPUT.PUT_LINE('Debug: Search term: "' || v_search_term || '"');
    DBMS_OUTPUT.PUT_LINE('Debug: Regex pattern: "' || v_search_term_regex || '"');
    DBMS_OUTPUT.PUT_LINE('Debug: Offset: ' || v_offset);

    -- Step 3: Generate the embedding vector for the search term
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
        DBMS_OUTPUT.PUT_LINE('Debug: Vector generated successfully.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error generating vector for search term: "' || v_search_term || '". Details: ' || SQLERRM);
            RETURN;
    END;

    -- Step 4: Check total available items for context
    BEGIN
        SELECT COUNT(*) 
        INTO v_total_items 
        FROM AI_ICITEM ai 
        WHERE ai.vector_desc IS NOT NULL 
        AND ai."DESC" IS NOT NULL;
        
        DBMS_OUTPUT.PUT_LINE('Debug: Total items with vectors: ' || v_total_items);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Warning: Could not count total items. Details: ' || SQLERRM);
    END;

    -- Step 5: Run the optimized hybrid search
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('--- Hybrid Search Results for: "' || v_search_term || '" ---');
    DBMS_OUTPUT.PUT_LINE('--- Page ' || v_page_number || ' of ' || v_top_n || ' results per page ---');
    DBMS_OUTPUT.PUT_LINE('');

    BEGIN
        OPEN c_hybrid_search(v_query_vector, v_search_term_regex, v_offset, v_top_n);
        LOOP
            FETCH c_hybrid_search INTO rec;
            EXIT WHEN c_hybrid_search%NOTFOUND;

            v_count := v_count + 1;
            DBMS_OUTPUT.PUT_LINE(
                v_count || '. ITEMNO: ' || rec.itemno ||
                ' | DESC: ' || SUBSTR(rec."DESC", 1, 50) ||
                CASE WHEN LENGTH(rec."DESC") > 50 THEN '...' ELSE '' END
            );
            DBMS_OUTPUT.PUT_LINE(
                '   TOTAL_SCORE: ' || TO_CHAR(rec.total_score, '999.99') ||
                ' | SIM: ' || TO_CHAR(rec.similarity_score, '99.99') ||
                ' | KEY: ' || TO_CHAR(rec.keyword_score, '99.99') ||
                ' | STK: ' || TO_CHAR(rec.stock_score, '99.99') ||
                ' | BRD: ' || TO_CHAR(rec.brand_score, '99.99') ||
                ' | QTY: ' || rec.stock_qty
            );
            
            -- Show synonyms if they exist and contributed to the score
            IF rec.SYNONYMS IS NOT NULL AND rec.keyword_score > 0 THEN
                DBMS_OUTPUT.PUT_LINE('   SYNONYMS: ' || SUBSTR(rec.SYNONYMS, 1, 60));
            END IF;
            
            DBMS_OUTPUT.PUT_LINE('');
        END LOOP;
        CLOSE c_hybrid_search;
    EXCEPTION
        WHEN OTHERS THEN
            IF c_hybrid_search%ISOPEN THEN
                CLOSE c_hybrid_search;
            END IF;
            DBMS_OUTPUT.PUT_LINE('Error during search execution: ' || SQLERRM);
            RETURN;
    END;

    DBMS_OUTPUT.PUT_LINE('--- End of Results ---');

    -- Step 6: Provide helpful feedback
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('No results found for page ' || v_page_number || '.');
        DBMS_OUTPUT.PUT_LINE('Suggestions:');
        DBMS_OUTPUT.PUT_LINE('1. Try a different search term');
        DBMS_OUTPUT.PUT_LINE('2. Check if the search term exists in the database');
        DBMS_OUTPUT.PUT_LINE('3. Verify that items have valid vector embeddings');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Found ' || v_count || ' results on page ' || v_page_number || '.');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        -- Final error handler
        IF c_hybrid_search%ISOPEN THEN
            CLOSE c_hybrid_search;
        END IF;
        DBMS_OUTPUT.PUT_LINE('An unexpected error occurred: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Error Stack: ' || DBMS_UTILITY.FORMAT_ERROR_STACK);
END;
/