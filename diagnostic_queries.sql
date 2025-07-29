-- Diagnostic queries to find the correct column names

-- 1. Check if the table exists and get its structure
SELECT table_name, owner 
FROM all_tables 
WHERE table_name = 'OEINVH' 
  AND owner = 'SFLDAT';

-- 2. Get all columns from OEINVH table
SELECT column_name, data_type, data_length, nullable
FROM all_tab_columns 
WHERE table_name = 'OEINVH' 
  AND owner = 'SFLDAT'
ORDER BY column_id;

-- 3. Look for date-related columns specifically
SELECT column_name, data_type, data_length
FROM all_tab_columns 
WHERE table_name = 'OEINVH' 
  AND owner = 'SFLDAT'
  AND (data_type LIKE '%DATE%' 
       OR column_name LIKE '%DATE%' 
       OR column_name LIKE '%INV%'
       OR column_name LIKE '%EXP%'
       OR column_name LIKE '%DOC%')
ORDER BY column_id;

-- 4. Check for common date column patterns
SELECT column_name, data_type
FROM all_tab_columns 
WHERE table_name = 'OEINVH' 
  AND owner = 'SFLDAT'
  AND (column_name IN ('INVDATE', 'INV_DATE', 'INVOICE_DATE', 'DOC_DATE', 'DATE_CREATED', 'CREATED_DATE')
       OR column_name IN ('EXPDATE', 'EXP_DATE', 'EXPIRY_DATE', 'DUE_DATE'))
ORDER BY column_name;

-- 5. Sample a few rows to see the data format
SELECT * FROM SFLDAT.OEINVH WHERE ROWNUM <= 5;

-- 6. Check if there are any date columns with numeric data
SELECT column_name, data_type, data_length
FROM all_tab_columns 
WHERE table_name = 'OEINVH' 
  AND owner = 'SFLDAT'
  AND data_type IN ('NUMBER', 'VARCHAR2', 'CHAR')
  AND (column_name LIKE '%DATE%' OR column_name LIKE '%INV%')
ORDER BY column_id;