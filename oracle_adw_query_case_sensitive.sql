-- Oracle ADW Query with case-sensitive column names
-- Using quoted identifiers to handle case sensitivity

SELECT 
    TO_CHAR(TO_DATE(IH."INVDATE", 'YYYYMMDD'), 'DD/MM/YY') AS INVDATE,
    'IN' AS TYPE,
    INVNUMBER,
    IH.SHINUMBER,
    IH.ORDNUMBER,
    TO_CHAR(TO_DATE(IH."EXPDATE", 'YYYYMMDD'), 'DD/MM/YY') AS EXPDATE,
    PONUMBER,
    REFERENCE,
    IH."DESC",
    CUSTOMER,
    NAMECUST,
    IH."LOCATION",
    IH.SHIPVIA,
    INVNETNOTX AS SUBTOTAL,
    INVETAXTOT AS GST,
    INVNETWTX AS TOTAL,
    ID.ITEM,
    ID."DESC",
    ID.QTYSHIPPED AS QTY,
    INVUNIT AS INVUOM,
    CAST(UNITCONV AS NUMBER(9,2)) AS UNITCONV,
    ID.BASEUNIT,
    CAST(ID.PRIBASPRC AS NUMBER(9,2)) AS PRIBASPRC,
    CAST(ID.UNITPRICE AS NUMBER(9,2)) AS UNITPRICE,
    CAST(ID.PRIUNTPRC AS NUMBER(9,2)) AS PRIUNTPRC,
    ID.PRICEOVER,
    CASE 
        WHEN CAST(ID.PRIUNTPRC AS NUMBER(9,2)) = CAST(ID.PRIBASPRC AS NUMBER(9,2)) THEN 1
        WHEN ID.PRICEOVER = 1 THEN 2
        WHEN CONTRACT_PRICE.CUSTNO IS NULL AND CAST(NVL(SalePrice.UNITPRICE,0) AS NUMBER(9,2)) = CAST(ID.PRIUNTPRC AS NUMBER(9,2)) THEN 6
        WHEN CONTRACT_PRICE.CUSTNO IS NOT NULL THEN
            CASE 
                WHEN CAST(NVL(SalePrice.UNITPRICE,0) AS NUMBER(9,2)) = CAST(ID.PRIUNTPRC AS NUMBER(9,2)) THEN 6
                ELSE
                    CASE 
                        WHEN CONTRACT_PRICE.PRICETYPE = 1 THEN 3
                        WHEN CONTRACT_PRICE.PRICETYPE = 2 THEN 4
                        WHEN CONTRACT_PRICE.PRICETYPE = 6 THEN 5
                        ELSE 5
                    END
            END
        ELSE 5
    END AS PRICETYPE,
    CAST(CASE WHEN ID.ACCTSET = 'CHILMT' THEN ID.STDCOST ELSE ID.UNITCOST END AS NUMBER(9,2)) AS UNITCOST,
    CAST(UNITWEIGHT AS NUMBER(9,2)) AS UNITWEIGHT,
    CAST(EXTWEIGHT AS NUMBER(9,2)) AS EXT_WEIGHT,
    CAST((ID.QTYSHIPPED * UNITCONV) AS NUMBER(9,2)) AS EXT_BASEQTY,
    CAST(ID.EXTINVMISC AS NUMBER(9,2)) AS EXT_PRICE,
    IH.PRICELIST,
    IH.SALESPER1 AS REP_CODE,
    CASE 
        WHEN ScanBackClaimPromo.Item_No IS NOT NULL THEN ScanBackClaimPromo.Price
        ELSE
            CASE 
                WHEN ScanBackClaimDAY.Item_No IS NOT NULL THEN ScanBackClaimDay.Price
                ELSE 0
            END
    END AS UNIT_CLAIMBACK,
    ID.UNITCOST - CASE 
        WHEN ScanBackClaimPromo.Item_No IS NOT NULL THEN ScanBackClaimPromo.Price
        ELSE
            CASE 
                WHEN ScanBackClaimDAY.Item_No IS NOT NULL THEN ScanBackClaimDay.Price
                ELSE 0
            END
    END AS NETUNITCOST,
    CAST(
        (
            ID.UNITCOST - CASE 
                WHEN ScanBackClaimPromo.Item_No IS NOT NULL THEN ScanBackClaimPromo.Price
                ELSE
                    CASE 
                        WHEN ScanBackClaimDAY.Item_No IS NOT NULL THEN ScanBackClaimDay.Price
                        ELSE 0
                    END
            END
        ) * ID.QTYSHIPPED AS NUMBER(9,2)
    ) AS NET_EXT_COST,
    (((ID.UNITPRICE-ID.UNITCOST)/ID.UNITPRICE)*100) AS MARGIN
FROM SFLDAT.OEINVH IH
    INNER JOIN ARCUS A ON IH.CUSTOMER = A.IDCUST
    INNER JOIN OEINVD ID ON IH.INVUNIQ = ID.INVUNIQ AND UNITPRICE <> 0
    LEFT JOIN (
        SELECT CP.Item_No, SUM(Price) AS Price
        FROM SFLDAT.tblScanBackClaimPromo CP
        WHERE CP.Item_No = ID.ITEM
            AND TO_DATE(IH."INVDATE", 'YYYYMMDD') BETWEEN CP.Start_Date AND CP.End_Date
            AND (
                (CP.Cust_Code = IH.CUSTOMER AND (CP.Cust_Grp = '' OR CP.Cust_Grp = A.IDGRP) AND (CP.Branches = '' OR CP.Branches = A.PRIMSHIPTO))
                OR
                (CP.Cust_Grp = A.IDGRP AND (CP.Cust_Code = '' OR CP.Cust_Code = IH.CUSTOMER) AND (CP.Branches = '' OR CP.Branches = A.PRIMSHIPTO))
                OR
                (CP.Branches = A.PRIMSHIPTO AND (CP.Cust_Code = '' OR CP.Cust_Code = IH.CUSTOMER) AND (CP.Cust_Grp = '' OR CP.Cust_Grp = A.IDGRP))
                OR
                (CP.Cust_Code = '' AND CP.CUST_GRP = '' AND CP.Branches = '')
            )
            AND INSTR(CP.ExIdGrp, RTRIM(A.IDGRP), 1) = 0
            AND INSTR(CP.ExIdCust, RTRIM(IH.CUSTOMER), 1) = 0
        GROUP BY CP.Item_No
    ) ScanBackClaimPromo ON ScanBackClaimPromo.Item_No = ID.ITEM
    LEFT JOIN (
        SELECT CD.Item_No, SUM(Price) AS Price
        FROM SFLDAT.tblScanBackClaimDAY CD
        WHERE CD.Item_No = ID.ITEM
            AND TO_DATE(IH."INVDATE", 'YYYYMMDD') BETWEEN CD.Start_Date AND CD.End_Date
            AND (
                (CD.Cust_Code = IH.CUSTOMER AND (CD.CUST_GRP = '' OR CD.Cust_Grp = A.IDGRP) AND (CD.Branches = '' OR CD.Branches = A.PRIMSHIPTO))
                OR
                (CD.Cust_Grp = A.IDGRP AND (CD.Cust_Code = '' OR CD.Cust_Code = IH.CUSTOMER) AND (CD.Branches = '' OR CD.Branches = A.PRIMSHIPTO))
                OR
                (CD.Branches = A.PRIMSHIPTO AND (CD.Cust_Code = '' OR CD.Cust_Code = IH.CUSTOMER) AND (CD.Cust_Grp = '' OR CD.Cust_Grp = A.IDGRP))
                OR
                (CD.Cust_Code = '' AND CD.CUST_GRP = '' AND CD.Branches = '')
            )
        GROUP BY CD.Item_No
    ) ScanBackClaimDAY ON ScanBackClaimDAY.Item_No = ID.ITEM
    LEFT JOIN (
        SELECT *
        FROM SFLDAT.ICPRICP I
        WHERE I.ITEMNO = ID.ITEM
            AND I.PRICELIST = IH.PRICELIST
            AND I.DPRICETYPE = 1
            AND I.CURRENCY = 'NZD'
    ) ListPrice ON ListPrice.ITEMNO = ID.ITEM
    LEFT JOIN (
        SELECT *
        FROM SFLDAT.ICPRICP I
        WHERE I.ITEMNO = ID.ITEM
            AND I.PRICELIST = IH.PRICELIST
            AND I.DPRICETYPE = 2
            AND I.CURRENCY = 'NZD'
            AND TO_DATE(IH."INVDATE", 'YYYYMMDD') BETWEEN I.SALESTART AND I.SALEEND
    ) SalePrice ON SalePrice.ITEMNO = ID.ITEM
    LEFT JOIN (
        SELECT *
        FROM SFLDAT.ICCUPR CON
        WHERE CON.CUSTNO = IH.CUSTOMER
            AND CON.ITEMNO = ID.ITEM
            AND TO_DATE(IH."INVDATE", 'YYYYMMDD') BETWEEN CON.STARTDATE AND CON.EXPIRE
            AND CON.CUSTTYPE = 1
    ) CONTRACT_PRICE ON CONTRACT_PRICE.CUSTNO = IH.CUSTOMER AND CONTRACT_PRICE.ITEMNO = ID.ITEM
WHERE IH."INVDATE" > 20250729
-- AND INVNUMBER = 'IN9549099'  -- Uncomment to filter by specific invoice number