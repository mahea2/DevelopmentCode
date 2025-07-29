# Oracle ADW ORDS API Solution for OEINVH

## Problem Statement
You need to create a REST API endpoint in Oracle ADW using ORDS that can:
1. Return all records when no parameters are passed
2. Filter by `invuniq` when that parameter is provided
3. Filter by `customer` when that parameter is provided

## Issue with Original Query
The original query used OR logic:
```sql
SELECT * FROM SFLDAT.OEINVH 
WHERE NVL(NULLIF(:invuniq, ''), invuniq) = invuniq 
   OR NVL(NULLIF(:customer, ''), customer) = customer
```

This would return records matching EITHER condition, not the intended behavior.

## Solution
The corrected query uses AND logic with proper NULL handling:
```sql
SELECT * FROM SFLDAT.OEINVH 
WHERE (:invuniq IS NULL OR :invuniq = '' OR invuniq = :invuniq)
  AND (:customer IS NULL OR :customer = '' OR customer = :customer)
```

## How It Works
- When no parameters are passed: Both conditions evaluate to TRUE, returning all records
- When `invuniq` is provided: Only records matching that `invuniq` are returned
- When `customer` is provided: Only records matching that `customer` are returned
- When both are provided: Only records matching both conditions are returned

## API Endpoints

### Base URL
`https://testitrack.servicefoods.co.nz/ords/salesforceext/sfldat/oeinvh`

### Usage Examples

1. **Get all records:**
   ```
   GET https://testitrack.servicefoods.co.nz/ords/salesforceext/sfldat/oeinvh
   ```

2. **Filter by invuniq:**
   ```
   GET https://testitrack.servicefoods.co.nz/ords/salesforceext/sfldat/oeinvh?invuniq=YOUR_INVUNIQ_VALUE
   ```

3. **Filter by customer:**
   ```
   GET https://testitrack.servicefoods.co.nz/ords/salesforceext/sfldat/oeinvh?customer=YOUR_CUSTOMER_VALUE
   ```

4. **Filter by both parameters:**
   ```
   GET https://testitrack.servicefoods.co.nz/ords/salesforceext/sfldat/oeinvh?invuniq=YOUR_INVUNIQ_VALUE&customer=YOUR_CUSTOMER_VALUE
   ```

## Setup Instructions

1. **Run the setup script:**
   ```sql
   @ords_oeinvh_setup.sql
   ```

2. **Grant necessary privileges (as DBA or schema owner):**
   ```sql
   GRANT SELECT ON SFLDAT.OEINVH TO ORDS_PUBLIC_USER;
   ```

3. **Verify the configuration:**
   ```sql
   SELECT 
       m.module_name,
       t.pattern,
       h.method,
       h.source_type,
       h.source
   FROM user_ords_modules m
   JOIN user_ords_templates t ON m.module_id = t.module_id
   JOIN user_ords_handlers h ON t.template_id = h.template_id
   WHERE m.module_name = 'salesforceext'
     AND t.pattern = 'sfldat/oeinvh';
   ```

## Alternative Query Approaches

### Option 1: Using CASE WHEN
```sql
SELECT * 
FROM SFLDAT.OEINVH 
WHERE (CASE 
    WHEN :invuniq IS NOT NULL AND :invuniq != '' THEN 
        CASE WHEN invuniq = :invuniq THEN 1 ELSE 0 END
    WHEN :customer IS NOT NULL AND :customer != '' THEN 
        CASE WHEN customer = :customer THEN 1 ELSE 0 END
    ELSE 1
END) = 1;
```

### Option 2: Using NVL (Simplified)
```sql
SELECT * 
FROM SFLDAT.OEINVH 
WHERE (:invuniq IS NULL OR :invuniq = '' OR invuniq = :invuniq)
  AND (:customer IS NULL OR :customer = '' OR customer = :customer);
```

## Response Format
The API will return JSON in the following format:
```json
{
  "items": [
    {
      "invuniq": "value1",
      "customer": "customer1",
      // ... other fields
    },
    {
      "invuniq": "value2", 
      "customer": "customer2",
      // ... other fields
    }
  ],
  "hasMore": false,
  "limit": 25,
  "offset": 0,
  "count": 2,
  "links": [
    {
      "rel": "self",
      "href": "https://testitrack.servicefoods.co.nz/ords/salesforceext/sfldat/oeinvh"
    }
  ]
}
```

## Troubleshooting

1. **Check ORDS status:**
   ```sql
   SELECT * FROM user_ords_modules WHERE module_name = 'salesforceext';
   ```

2. **Verify table access:**
   ```sql
   SELECT COUNT(*) FROM SFLDAT.OEINVH;
   ```

3. **Test with specific values:**
   ```sql
   SELECT * FROM SFLDAT.OEINVH 
   WHERE (:invuniq IS NULL OR :invuniq = '' OR invuniq = :invuniq)
     AND (:customer IS NULL OR :customer = '' OR customer = :customer);
   ```

## Files Included
- `ords_oeinvh_setup.sql` - Complete ORDS setup script
- `ords_api_solution.sql` - Query solutions and examples
- `README.md` - This documentation