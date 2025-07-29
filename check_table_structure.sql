-- Check the structure of OEINVH table to find the correct date column name
SELECT column_name, data_type, data_length
FROM user_tab_columns 
WHERE table_name = 'OEINVH'
ORDER BY column_id;

-- Also check for any date-related columns
SELECT column_name, data_type, data_length
FROM user_tab_columns 
WHERE table_name = 'OEINVH' 
  AND (data_type LIKE '%DATE%' OR column_name LIKE '%DATE%' OR column_name LIKE '%INV%')
ORDER BY column_id;

-- Check if the table exists in the SFLDAT schema
SELECT column_name, data_type, data_length
FROM all_tab_columns 
WHERE table_name = 'OEINVH' 
  AND owner = 'SFLDAT'
ORDER BY column_id;