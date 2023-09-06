DECLARE @Timezone VARCHAR(255) = (SELECT Timezone FROM CONTROL WITH (NOLOCK));
---------------------------------------------------------#Lines-------------------------------------------------------------------
    SELECT
		il.UniqueId,
        dbo.PurchaseOrder_SupplierInvoice.PurchaseOrderId,
        purchaseorder_supplierinvoice.invoicenumber,
        tc.Code, 
        tc.value as [vatcodevalue],
        CASE PurchaseOrder_SupplierInvoice.Type 
            WHEN 1 
                THEN -(ROUND(il.PricePerUnit * il.Quantity, 2))
            WHEN 0 
                THEN (ROUND(il.PricePerUnit * il.Quantity, 2)) 
            END AS TotalExcludingVat, 
        CASE PurchaseOrder_SupplierInvoice.Type 
            WHEN 1 
                THEN -(COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0)) 
            WHEN 0 
                THEN (COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0)) 
            END + coalesce(discount_amount,0) AS [Discount ammount],
        CASE PurchaseOrder_SupplierInvoice.Type 
            WHEN 1 
                THEN -(ROUND(il.Quantity * il.PricePerUnit, 2) - COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0))  
            WHEN 0 
                THEN (ROUND(il.Quantity * il.PricePerUnit, 2) - COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0))
            END - coalesce(discount_amount,0) AS TotalExcludingVatIncludingDiscount,
        CASE 
            WHEN IL.OverriddenTaxAmount IS NOT NULL AND PurchaseOrder_SupplierInvoice.Type  = 1 
                THEN -IL.OverriddenTaxAmount
            WHEN IL.OverriddenTaxAmount IS NOT NULL AND PurchaseOrder_SupplierInvoice.Type  = 0 
                THEN IL.OverriddenTaxAmount
            WHEN IL.OverriddenTaxAmount IS NULL AND PurchaseOrder_SupplierInvoice.Type  = 1 
                THEN -(COALESCE (ROUND(((ROUND(il.Quantity * il.PricePerUnit, 2) - COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0)) - coalesce(discount_amount,0)
                ) * (tc.Value / 100.0), 2), 0))
            WHEN IL.OverriddenTaxAmount IS NULL AND PurchaseOrder_SupplierInvoice.Type  = 0
                THEN (COALESCE (ROUND(((ROUND(il.Quantity * il.PricePerUnit, 2) - COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0)) - coalesce(discount_amount,0)
                ) * (tc.Value / 100.0), 2), 0))
            END AS TotalVatAmount,
        CASE 
            WHEN IL.OverriddenTaxAmount IS NOT NULL AND PurchaseOrder_SupplierInvoice.Type = 1
                THEN -(ROUND(il.Quantity * il.PricePerUnit, 2) - COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0) -coalesce(discount_amount,0)  + 
                IL.OverriddenTaxAmount
                )
            WHEN IL.OverriddenTaxAmount IS NULL AND PurchaseOrder_SupplierInvoice.Type = 1
                THEN -(ROUND(il.Quantity * il.PricePerUnit, 2) - COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0) -coalesce(discount_amount,0)  + 
                COALESCE (ROUND(((ROUND(il.Quantity * il.PricePerUnit, 2) - COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0)) 
                -coalesce(discount_amount,0))
                * (tc.Value / 100.0), 2), 0)
                )
            WHEN IL.OverriddenTaxAmount IS NOT NULL AND PurchaseOrder_SupplierInvoice.Type = 0
                THEN (ROUND(il.Quantity * il.PricePerUnit, 2) - COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0) -coalesce(discount_amount,0) + 
                IL.OverriddenTaxAmount
                )
            WHEN IL.OverriddenTaxAmount IS NULL AND PurchaseOrder_SupplierInvoice.Type = 0
                THEN (ROUND(il.Quantity * il.PricePerUnit, 2) - COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0) -coalesce(discount_amount,0) + 
                COALESCE (ROUND(((ROUND(il.Quantity * il.PricePerUnit, 2) - COALESCE (ROUND(ROUND(il.Quantity * il.PricePerUnit, 2) * (il.Discount_percentage / 100.0), 2), 0)) -coalesce(discount_amount,0)
                )
                * (tc.Value / 100.0), 2), 0))
            END  AS TotalIncludingVat, 
        nominalcodes.code AS nomcode,
        il.UniqueId AS InvoiceLineUniqueID,
        dbo.PurchaseOrder_SupplierInvoice.Type
		INTO #Lines
    FROM  dbo.PurchaseOrder_SupplierInvoice 
        INNER JOIN dbo.PurchaseOrder_SupplierInvoice_Lines AS il ON il.SupplierInvoiceId = purchaseorder_supplierinvoice.uniqueid 
        LEFT JOIN dbo.TaxCodes AS tc ON tc.UniqueId = il.TaxCodeId 
        LEFT JOIN dbo.NominalCodes ON il.NominalCodeId = nominalcodes.uniqueid;

		CREATE NONCLUSTERED INDEX IX_LI ON #Lines (PurchaseOrderId);
------------------------------------------------------------#TotalINVTable---------------------------------------------------------------------
SELECT
	SPOL.UniqueId,
	CASE WHEN SPI.[Type]=0 THEN SPOL.Quantity * SPOL.PricePerUnit ELSE -1*SPOL.Quantity * SPOL.PricePerUnit END AS [Total Excluding VAT],
	TC.[Description] AS [tax code],
	CASE WHEN SPI.[Type]=0 THEN (SPOL.Quantity * SPOL.PricePerUnit)*TC.[Value]/100 ELSE 
	-1*(SPOL.Quantity * SPOL.PricePerUnit)*TC.[Value]/100 END AS [VAT Amount]
INTO
	#TotalINVTable
FROM
	PurchaseOrder_SubContractorInvoice AS SPI
	LEFT JOIN PurchaseOrder_SubContractorInvoice_Lines SPOL ON SPI.UniqueId=SPOL.SubContractorInvoiceId
	LEFT JOIN TaxCodes TC ON TC.UniqueId=SPOL.TaxCodeId

CREATE NONCLUSTERED INDEX IND_TotalINVTable ON #TotalINVTable (UniqueId)
------------------------------------------------------------#PurchaseInvoices---------------------------------------------------------------------
SELECT
	POSI.UniqueId AS [ID],
	CASE
		WHEN POSI.[Type] = 0
			THEN 'PI'  
		ELSE 'PC' 
	END AS [Type],
	SU.AccountNumber AS [AccountNumber],
	CASE 
		WHEN NC.Code IS NOT NULL 
			THEN NC.Code
	END AS [NOMINAL_CODE],
	POL.PartNumber AS [Department Code],
	CONVERT(VARCHAR,dbo.getlocaliseddate(POSI.[Date],@Timezone), 103) AS [InvoiceDate],
	POSI.InvoiceNumber AS [InvoiceNumber],
	CONCAT_WS('/',J.ID, PO.PONumber) AS [JobId/OrderNo],
	ABS(LI.[TotalExcludingVatIncludingDiscount]) AS [Value],
	LI.[Code] AS [Tax Code],
	ABS(LI.[TotalVatAmount]) AS [VAT],
	POSI.PassedtoAccounts,
	POSIL.[Description] AS [Invoice Line Description]

INTO #PurchaseInvoices

FROM
	PurchaseOrder_SupplierInvoice AS [POSI]
	LEFT JOIN PurchaseOrder_SupplierInvoice_Lines AS [POSIL] ON POSIL.SupplierInvoiceId = POSI.UniqueId
	LEFT JOIN PurchaseOrder_Lines AS [POL] ON POL.SupplierInvoiceLineId = POSIL.UniqueId OR POL.SupplierCreditLineId = POSIL.UniqueId
	LEFT JOIN #Lines AS [LI] ON LI.UniqueId = POSIL.UniqueId
	LEFT JOIN PurchaseOrder AS [PO] ON PO.UniqueId = POSI.PurchaseOrderId
	LEFT JOIN NominalCodes AS [NC] ON NC.UniqueId = POSIL.NominalCodeId
	LEFT JOIN Job AS [J] ON J.AutoId = PO.JobAutoId
	LEFT JOIN Supplier AS SU ON SU.Id=PO.SupplierId

UNION ALL

SELECT
	POSI.UniqueId AS [ID],
	CASE
		WHEN POSI.[Type] = 0
			THEN 'PI'  
		ELSE 'PC'
	END AS [Type],
	SU.AccountNumber AS [AccountNumber],
	CASE 
		WHEN NC.Code IS NOT NULL 
			THEN NC.Code
	END AS [NOMINAL_CODE],
	'' AS [Department Number],
	CONVERT(VARCHAR,dbo.getlocaliseddate(POSI.[Date],@Timezone), 103) AS [InvoiceDate],
	POSI.InvoiceNumber AS [InvoiceNumber],
	CONCAT_WS('/',J.ID,SCPO.PONumber) AS [JobId/OrderNo],
	ABS(TI.[Total Excluding VAT]) AS [Value],
	TI.[tax code] AS [Tax Code],
	TI.[VAT Amount] AS [VAT],
	POSI.PassedtoAccounts,
	POSIL.[Description] AS [Invoice Line Description]
FROM
	PurchaseOrder_SubContractorInvoice AS [POSI]
	LEFT JOIN PurchaseOrder_SubContractorInvoice_Lines AS [POSIL] ON POSIL.SubcontractorInvoiceId = POSI.UniqueId
	LEFT JOIN SubContractor_PurchaseOrder_Lines AS [SCPOL] ON SCPOL.InvoiceLineId = POSIL.UniqueId OR SCPOL.CreditLineId = POSIL.UniqueId
	LEFT JOIN #TotalINVTable AS [TI] ON TI.UniqueId = POSIL.UniqueId
	LEFT JOIN SubContractor_PurchaseOrder AS [SCPO] ON SCPO.UniqueId = POSI.PurchaseOrderId
	LEFT JOIN NominalCodes AS [NC] ON NC.UniqueId = POSIL.NominalCodeId
	LEFT JOIN Job AS [J] ON J.AutoId = SCPO.JobAutoId
	LEFT JOIN SubContractor AS SU ON SU.Id=SCPO.SubContractorId

CREATE NONCLUSTERED INDEX IND_PurchaseInvoices ON #PurchaseInvoices (ID);
------------------------------------------------------------Main Query---------------------------------------------------------------------

SELECT
	PIN.ID,
	PIN.[Type],
	PIN.AccountNumber,
	PIN.NOMINAL_CODE,
	PIN.[Department Code],
	PIN.InvoiceDate,
	PIN.InvoiceNumber,
	PIN.[JobId/OrderNo],
	PIN.[Value],
	PIN.[Tax Code],
	PIN.VAT,
	LEFT(PIN.[Invoice Line Description],30) AS [Invoice Line Description]
FROM
	#PurchaseInvoices AS [PIN]
WHERE
	PIN.[Value] <> 0
	AND PIN.PassedToAccounts = 0
ORDER BY 
	PIN.InvoiceNumber DESC
