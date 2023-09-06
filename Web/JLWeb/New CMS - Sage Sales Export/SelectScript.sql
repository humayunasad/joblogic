DECLARE @JGTimezone VARCHAR(255) = (SELECT Timezone FROM CONTROL WITH (NOLOCK));

-----------------------------------------------------------------------------------------------------------------------------------
SELECT
    Il.[InvoiceGuid],
    Il.[Qty],
    Il.[Price], 
    Il.[Discount_Amount], 
    Il.[Discount_Percentage], 
    Il.nominalcodeid ,
    Il.taxcodeid,
    Il.details,
    Il.autoid,
    BI.creditnote as [Credit], 
    BI.isdraft as [Draft],
    BI.ID as [ID],
    i.JobAutoId, 
    'S' AS [TypeOfInvoice], 
    Il.UniqueID AS [LineUniqueID], 
    CR.UniqueID  AS [CreditedInvoiceLineUniqueID],
	CASE
		WHEN [Il].Discount_Amount IS NOT NULL AND [Il].Price=0 THEN 1 
		WHEN [Il].Discount_Percentage IS NOT NULL AND [Il].Price=0 THEN 2 
	ELSE 0 
	END AS [Discount Line]
INTO #InvoiceLineUnion_RSL
FROM [Invdets] AS [Il]
LEFT JOIN baseinvoice AS [BI] ON Il.InvoiceGuid = BI.uniqueid
LEFT JOIN Invoice AS [I] ON Il.InvoiceGuid = I.UniqueID
LEFT JOIN Invdets AS [CR] ON CR.AutoID = Il.CreditedInvoiceLineId
UNION ALL
SELECT
    IL.[InvoiceId], 
    IL.[Quantity] AS [Qty], 
    IL.[PricePerUnit] AS [Price], 
    IL.[Discount_Amount], 
    IL.[Discount_Percentage],
    Il.nominalcodeid ,
    Il.taxcodeid, 
    Il.description as [Details],
    ''as autoid,
    BI.creditnote  as [Credit],
    BI.isdraft as [Draft], 
    BI.id as [ID],
    NULL AS JobAutoId,
    'P' AS [TypeOfInvoice],
    Il.UniqueId AS [LineUniqueID],
    NULL AS [CreditedInvoiceLineUniqueID],
	NULL AS [Discount Line]
FROM [PPMContract_InvoiceLines] AS [Il]
LEFT JOIN baseinvoice AS [BI] ON Il.InvoiceId = BI.uniqueid
	
UNION ALL
        
SELECT
    IL.[InvoiceGuid],
    IL.[Qty],
    IL.[Price],
    IL.[Discount_Amount],
    IL.[Discount_Percentage],
    Il.nominalcodeid ,
    Il.taxcodeid, 
    Il.details,
    '' as autoid,
    BI.creditnote as [Credit], 
    BI.isdraft as [Draft], 
    BI.ID as [ID],
    IL.JobAutoId AS JobAutoId,
    'C' AS [TypeOfInvoice], 
    Il.UniqueId AS [LineUniqueID], 
    Il.CreditedInvoiceLineGuid  AS [CreditedInvoiceLineUniqueID],
	NULL AS [Discount Line]
FROM [CustomerGrouped_InvoiceLine] AS [Il]
LEFT JOIN baseinvoice AS [BI] ON Il.InvoiceGuid = BI.uniqueid      

CREATE NONCLUSTERED INDEX IX_IL ON #InvoiceLineUnion_RSL ([InvoiceGuid])
SELECT
        IL.[InvoiceGuid], 
        TC.value AS [VATRate],
        TC.[code] AS [Taxcode],
        IL.[TaxcodeID],
        NC.[code] AS [nomcode],
        IL.[Details],
        IL.[Price] as [Unitvalue],
        IL.[Qty],
        IL.[Credit] as [CreditNote],
        IL.[Draft] as [IsDraft],
        IL.[ID],
        IL.autoid as [invdetautoid],
		IL.[Discount_Percentage] AS [EnteredPercentageDiscount],
		COALESCE(il.[Qty] * il.[Price],0)  AS [QTimesP],
		IL.JobAutoId,
		IL.[TypeOfInvoice],
		IL.[LineUniqueID],
		IL.[CreditedInvoiceLineUniqueID],
        IL.[Discount_Percentage],
        IL.[Discount_Amount],
		IL.[Discount Line]
		INTO #Calc_RSL
FROM #InvoiceLineUnion_RSL il
LEFT JOIN taxcodes AS [TC] on Il.taxcodeid = TC.uniqueid
LEFT JOIN nominalcodes AS [NC] on Il.nominalcodeid = NC.uniqueid

CREATE NONCLUSTERED INDEX IX_IL ON #Calc_RSL ([InvoiceGuid])

SELECT
        C.[InvoiceGuid], 
        C.[VATRate],
        C.[Taxcode],
        C.[TaxcodeID],
        C.[nomcode],
        C.[Details],
        C.[Unitvalue],
        C.[Qty],
        C.[CreditNote],
        C.[IsDraft],
        C.[ID],
        C.[invdetautoid],
        C.QTimesP AS [QTimesP],
		ROUND(
            CASE 
                WHEN (C.[Discount_Amount] IS NOT NULL) 
                    THEN C.QTimesP - C.[Discount_Amount]
                WHEN (C.[Discount_Percentage] IS NOT NULL) 
                    THEN C.QTimesP * (1 - (C.[Discount_Percentage] / 100))
                    ELSE C.QTimesP 
                END, 2)  AS [LineValue],
		C.[EnteredPercentageDiscount],
		C.QTimesP  AS [LineValueNoDiscount],
		C.JobAutoId,
		C.[TypeOfInvoice],
		C.[LineUniqueID],
		C.[CreditedInvoiceLineUniqueID],
		C.[Discount Line]
		INTO #Calc2_RSL
	FROM #Calc_RSL AS [C]

CREATE NONCLUSTERED INDEX IX_IL ON #Calc2_RSL ([InvoiceGuid])

SELECT
        C.[InvoiceGuid], 
        C.[VATRate],
        C.[Taxcode],
        C.[TaxcodeID],
        C.[nomcode],
        C.[Details],
        C.[Unitvalue],
        C.[Qty],
        C.[CreditNote],
        C.[IsDraft],
        C.[ID],
        C.[invdetautoid],
		C.LineValue AS [LineValue],
		C.[EnteredPercentageDiscount],
		C.QTimesP  AS [LineValueNoDiscount],
		C.QTimesP - C.LineValue AS [DiscountValue],
		C.LineValue * COALESCE(C.VATRate, 0) / 100  AS [VATValue],
		C.JobAutoId,
		C.[TypeOfInvoice],
		C.[LineUniqueID],
		C.[CreditedInvoiceLineUniqueID],
		C.[Discount Line]
		INTO #Calc3_RSL
	FROM #Calc2_RSL AS [C]

CREATE NONCLUSTERED INDEX IX_IL ON #Calc3_RSL ([InvoiceGuid])

SELECT
	C.InvoiceGuid,
	SUM(C.LineValue) AS [LineValue]
	INTO #Calc4_RSL
FROM
#Calc3_RSL AS C
GROUP BY C.InvoiceGuid

CREATE NONCLUSTERED INDEX IX_IL ON #Calc4_RSL ([InvoiceGuid])

SELECT
	C.LineUniqueID,
	C4.LineValue * C.EnteredPercentageDiscount / 100 AS [LineValue]
	INTO #Calc5_RSL
FROM
#Calc3_RSL AS C
INNER JOIN #Calc4_RSL AS C4 ON C4.InvoiceGuid=C.InvoiceGuid
WHERE C.[Discount Line] = 2

CREATE NONCLUSTERED INDEX IX_IL ON #Calc5_RSL (LineUniqueID)

SELECT
	C.[InvoiceGuid]
	,C.[vATrATE]
	,C.[Taxcode]
	,C.[TaxcodeID]
	,C.[nomcode]
	,C.[Details]
	,C.[Unitvalue]
	,C.[Qty]
	,C.[CreditNote]
	,C.[IsDraft]
	,C.[ID]
	,C.[invdetautoid]
	,CASE WHEN C.[Discount Line] IN (1,2) THEN 0 ELSE CAST(CASE C.[CreditNote] WHEN 1 THEN -C.[LineValue] ELSE C.[LineValue] END AS money) END AS [LineValue]
	,CAST(CASE C.[CreditNote] WHEN 1 THEN -C.[LineValueNoDiscount] ELSE C.[LineValueNoDiscount] END AS money) AS [LineValueNoDiscount]
	,CASE WHEN C.[Discount Line] IN (1,2) THEN 0 ELSE CAST(CASE C.[CreditNote] WHEN 1 THEN -C.[DiscountValue] ELSE C.[DiscountValue] END AS money) END AS [DiscountValue]
	,CASE 
		WHEN [EnteredPercentageDiscount] IS NOT NULL 
			THEN [EnteredPercentageDiscount]
		WHEN [DiscountValue] IS NOT NULL AND [LineValueNoDiscount] <> 0 
			THEN ROUND(100 - ((([LineValueNoDiscount] - [DiscountValue])/[LineValueNoDiscount]) * 100) ,2)
            ELSE 0
		    END AS [DiscountPercentageCalc]
	,CAST(CASE C.[CreditNote] WHEN 1 THEN -C.[VATValue] ELSE C.[VATValue] END AS money) AS [VATValue]
	,CASE WHEN C.[Discount Line] = 2 AND C.CreditNote = 0 THEN CAST(-C5.LineValue AS MONEY) WHEN C.[Discount Line] = 2 AND C.CreditNote = 1 THEN CAST(C5.LineValue AS MONEY) 
	ELSE CAST(CASE C.[CreditNote] WHEN 1 THEN -(C.[LineValue] + C.[VATValue]) ELSE (C.[LineValue] + C.[VATValue]) END AS money) END AS [IncludingVat]
	,CASE WHEN C.[Discount Line] IN (1,2) THEN 1 ELSE 0 END AS [Global Discount Line]
	,C.JobAutoId
	,C.[TypeOfInvoice]
	,C.[LineUniqueID]
	,C.[CreditedInvoiceLineUniqueID]
	INTO #RoundedSalesInvoiceLines
FROM #Calc3_RSL AS [C]
LEFT JOIN #Calc5_RSL AS C5 ON C5.LineUniqueID = C.LineUniqueID

CREATE NONCLUSTERED INDEX IX_IL ON #RoundedSalesInvoiceLines ([InvoiceGuid])
-------------------------------------------------#SalesInvoiceTotals---------------------------------------------------------------------------------
SELECT 
	0 AS [InvoiceType],
	C.[AutoLastId] AS [CustomerAutoId], 
	C.[ID] AS [CustomerId], 
	C.[Name] AS [CustomerName],
	S.[AutoId] AS [SiteAutoId], 
	S.[ID] AS [SiteId], 
	S.[Site],
	J.[ID] AS [JobId], 
	NULL AS [PPMContractId], 
	J.[ID] AS [ID], 
	J.AutoId AS JobAutoId,
	J.[Description],
	I.UserId, 
	'S' AS [TypeOfInvoice],
	BI.UniqueId AS [InvoiceGuid],
	IL.[Qty],
	IL.[Price], 
	IL.[Discount_Amount], 
	IL.[Discount_Percentage], 
	IL.TaxCodeId,
	BI.CreditNote AS [Credit],
	IL.NominalCodeId,
	IL.CreatedAt,
	IL.UniqueId AS [LineUniqueID],
	CASE
		WHEN [IL].Discount_Amount IS NOT NULL AND [IL].Price=0 THEN 1 
		WHEN [IL].Discount_Percentage IS NOT NULL AND [IL].Price=0 THEN 2 
		ELSE 0 
	END AS [Discount Line]
INTO #InvoiceLineUnion
FROM [Invoice] AS [I]
LEFT JOIN BaseInvoice AS [BI] ON I.UniqueId = BI.uniqueid
LEFT JOIN [Job] AS [J] ON J.[AutoId] = I.[JobAutoId]
LEFT JOIN Customer AS [C] ON C.[AutoLastID] = J.[CustomerAutoId]
LEFT JOIN [Contract] AS [S] ON S.[AutoId] = J.[SiteAutoId]
LEFT JOIN Invdets AS [IL] ON I.UniqueId = IL.InvoiceGuid
LEFT JOIN Invdets AS [CR] ON CR.AutoID = IL.CreditedInvoiceLineId

UNION ALL

SELECT
	 1 AS [InvoiceType],
	 C.[AutoLastId] AS [CustomerAutoId], 
	 C.[ID] AS [CustomerId], 
	 C.[Name] AS [CustomerName],
	 S.[AutoId] AS [SiteAutoId], 
	 S.[ID] AS [SiteId], 
	 S.[Site],
	 NULL AS [JobId], 
	 P.[UniqueId] AS [PPMContractId], 
	 P.[PPMContractNumber] AS [JobID], 
	 NULL AS JobAutoId,
	 P.[Description],
	 NULL AS [UserId], 
	 'P' AS [TypeOfInvoice],
	 BI.UniqueId AS [InvoiceGuid],
	 IL.[Quantity] AS [Qty], 
	 IL.[PricePerUnit] AS [Price], 
	 IL.[Discount_Amount], 
	 IL.[Discount_Percentage],
	 IL.TaxCodeId, 
	 BI.CreditNote AS [Credit],
	 IL.NominalCodeId,
	 IL.CreatedAt,
	 IL.UniqueId AS [LineUniqueID],
	 NULL AS [Discount Line]
FROM [PPMContract_Invoices] AS [I]
LEFT JOIN BaseInvoice AS [BI] ON I.UniqueId = BI.uniqueid
LEFT JOIN [PPMContract] AS [P] ON P.[UniqueId] = I.[PPMContractId]
LEFT JOIN Customer AS [C] ON C.[AutoLastID] = P.[CustomerAutoId]
LEFT JOIN [Contract] AS [S] ON S.[AutoId] = P.[SiteAutoId]
LEFT JOIN [PPMContract_InvoiceLines] AS [IL] ON I.UniqueId = IL.InvoiceId

UNION ALL

SELECT
	 2 AS [InvoiceType],
	 C.[AutoLastId] AS [CustomerAutoId], 
	 C.[ID] AS [CustomerId], 
	 C.[Name] AS [CustomerName],
	 NULL AS [SiteAutoId], 
	 NULL AS [SiteId], 
	 NULL AS [Site],
	 NULL AS [JobId], 
	 NULL AS [PPMContractId], 
	 NULL AS [JobNumber], 
	 NULL AS JobAutoId,
	 NULL AS [Description], 
	 NULL AS [UserId],  
	 'C' AS [TypeOfInvoice],
	 BI.UniqueId AS [InvoiceGuid],
	 IL.[Qty],
	 IL.[Price],
	 IL.[Discount_Amount],
	 IL.[Discount_Percentage],
	 IL.TaxCodeId, 
	 BI.CreditNote AS [Credit],
	 IL.NominalCodeId,
	 IL.CreatedAt,
	 IL.UniqueId AS [LineUniqueID],
	 NULL AS [Discount Line]
FROM [CustomerGrouped_Invoice] AS [I]
LEFT JOIN BaseInvoice AS [BI] ON I.UniqueId = BI.uniqueid   
LEFT JOIN Customer AS [C] ON C.[AutoLastID] = I.[CustomerAutoId]
LEFT JOIN [CustomerGrouped_InvoiceLine] AS [IL] ON I.UniqueId = IL.InvoiceGuid;
		   
CREATE NONCLUSTERED INDEX IX_ILU ON #InvoiceLineUnion (InvoiceGuid);

SELECT
	[TypeOfInvoice],
	IL.[CustomerAutoId],
	IL.[CustomerId],
	IL.[CustomerName], 
	IL.[SiteAutoId], 
	IL.[SiteId], 
	IL.[Site],
	IL.[PPMContractId],
	IL.[Jobid], 
	IL.JobAutoId,
	IL.[Description],
	IL.userid,
	IL.InvoiceType,
	IL.CreatedAt,
	IL.NominalCodeId,
	IL.[InvoiceGuid], 
	IL.[Price] AS [Unitvalue],
	IL.[Qty],
	IL.[Credit] AS [CreditNote],
	IL.[Discount_Percentage] AS [EnteredPercentageDiscount],
	COALESCE(IL.[Qty] * IL.[Price],0) AS [QTimesP],
	IL.[Discount_Percentage],
	IL.[Discount_Amount],
	TC.[Value] AS [VatRate],
	TC.Code AS [TaxCode],
	TC.UniqueId AS [TaxCodeId],
	NC.[Code] AS [NominalCode],
	IL.LineUniqueID,
	IL.[Discount Line]
INTO #Calc
FROM #InvoiceLineUnion AS [IL]
LEFT JOIN TaxCodes AS [TC] ON IL.taxcodeid = TC.UniqueId
LEFT JOIN NominalCodes AS [NC] ON IL.NominalCodeId = NC.UniqueId;

CREATE NONCLUSTERED INDEX IX_CC ON #Calc (InvoiceGuid);

SELECT
	[TypeOfInvoice],
	[CustomerAutoId],
	[CustomerId],
	[CustomerName],
	[SiteAutoId], 
	[SiteId], 
	[Site],
	[PPMContractId],
	[Jobid], 
	JobAutoId,
	[Description], 
	UserId,
	C.InvoiceType,
	C.CreatedAt,
	C.NominalCodeId,
	C.[InvoiceGuid], 
	C.[CreditNote],
	C.QTimesP AS [QTimesP],
	ROUND(
		CASE 
			WHEN (C.[Discount_Amount] IS NOT NULL) 
				THEN C.QTimesP - C.[Discount_Amount]
			WHEN (C.[Discount_Percentage] IS NOT NULL) 
				THEN C.QTimesP * (1 - (C.[Discount_Percentage] / 100))
				ELSE C.QTimesP 
			END, 2)  AS [LineValue],
	C.QTimesP AS [LineValueNoDiscount],
    C.[VatRate],
    C.[TaxCode],
    C.TaxCodeId,
    C.[Nominalcode],
	C.LineUniqueID,
	C.EnteredPercentageDiscount,
	C.[Discount Line]
INTO #Calc2
FROM #Calc AS [C];

CREATE NONCLUSTERED INDEX IX_CC2 ON #Calc2 (InvoiceGuid);

SELECT
	[TypeOfInvoice],
	[CustomerAutoId],
	[CustomerId],
	[CustomerName], 
	[SiteAutoId],
	[SiteId], 
	[Site],
	[PPMContractId],
	[JobId], 
	JobAutoId,
	[Description], 
	UserId,
	C.InvoiceType,
	C.NominalCodeId,
	C.[InvoiceGuid], 
	C.[CreditNote],
	C.LineValue AS [LineValue],
	C.QTimesP  AS [LineValueNoDiscount],
	C.QTimesP - C.LineValue AS [DiscountValue],
	C.LineValue * COALESCE(C.VATRate, 0) / 100  AS [VATValue],
    --FIRST_VALUE(C.[VatRate]) OVER(PARTITION BY C.InvoiceGuid ORDER BY C.CreatedAt DESC) AS [VatRate],
    --FIRST_VALUE(C.[TaxCode]) OVER(PARTITION BY C.InvoiceGuid ORDER BY C.CreatedAt DESC) AS [TaxCode],
    --FIRST_VALUE(C.[TaxCodeId]) OVER(PARTITION BY C.InvoiceGuid ORDER BY C.CreatedAt DESC) AS [TaxCodeId],
    --FIRST_VALUE(C.[NominalCode]) OVER(PARTITION BY C.InvoiceGuid ORDER BY C.CreatedAt DESC) AS [NominalCode],
	C.LineUniqueID,
	C.EnteredPercentageDiscount,
	C.[Discount Line]
INTO #Calc3
FROM #Calc2 AS [C];

CREATE NONCLUSTERED INDEX IX_CC3 ON #Calc3 (InvoiceGuid);

SELECT
	C.InvoiceGuid,
	SUM(C.LineValue) AS [LineValue]
INTO #CALC4
FROM #Calc3 AS C
GROUP BY C.InvoiceGuid;

CREATE NONCLUSTERED INDEX IX_CALC4 ON #CALC4 (InvoiceGuid);

SELECT
	C.LineUniqueID,
	C4.LineValue * C.EnteredPercentageDiscount / 100 AS [LineValue]
INTO #CALC5
FROM #Calc3 AS C
INNER JOIN #CALC4 AS C4 ON C4.InvoiceGuid=C.InvoiceGuid
WHERE C.[Discount Line]=2;

CREATE NONCLUSTERED INDEX IX_CALC5 ON #CALC5 (LINEUNIQUEID);

SELECT
	[TypeOfInvoice],
	[CustomerAutoId],
	[CustomerId],
	[CustomerName],
	[SiteAutoId], 
	[SiteId], 
	[Site],
	[PPMContractId],
	[Jobid], 
	JobAutoId,
	[Description], 
	UserId,
	C.InvoiceType,
	C.[InvoiceGuid],
	SUM(CAST(ROUND(CASE 
						WHEN C.[Discount Line] = 2 AND C.CreditNote = 0 THEN -C5.LineValue 
						WHEN C.[Discount Line] = 2 AND C.CreditNote = 1 THEN C5.LineValue
						WHEN C.[CreditNote] = 1 THEN -C.[LineValue] ELSE C.[LineValue] END ,2) AS money)) AS [ExcludingVat]
	,SUM(CAST(ROUND(CASE C.[CreditNote] WHEN 1 THEN -C.[LineValueNoDiscount] ELSE C.[LineValueNoDiscount] END ,2)  AS money)) AS [ValueNoDiscount]
	,SUM(CAST(ROUND(CASE 
						WHEN C.[Discount Line] = 2 AND C.CreditNote = 0 THEN C5.LineValue 
						WHEN C.[Discount Line] = 2 AND C.CreditNote = 1 THEN -C5.LineValue
						WHEN C.[CreditNote] = 1 THEN -C.[DiscountValue] ELSE C.[DiscountValue] END ,2)  AS money)) AS [DiscountValue]
	,SUM(CAST(ROUND(CASE C.[CreditNote] WHEN 1 THEN -C.[VATValue] ELSE C.[VATValue] END ,2)  AS money)) AS [VatAmount]
	,SUM(CAST(ROUND(CASE 
						WHEN C.[Discount Line] = 2 AND C.CreditNote = 0 THEN -C5.LineValue 
						WHEN C.[Discount Line] = 2 AND C.CreditNote = 1 THEN C5.LineValue
						WHEN C.[CreditNote] = 1 THEN -(C.[LineValue] + C.[VATValue]) ELSE (C.[LineValue] + C.[VATValue]) END ,2)  AS money)) AS [IncludingVat],
    --C.[vatrate],
    --C.[taxcode],
    --C.taxcodeid,
    --C.[Nominalcode],
	SUM(CASE 
		WHEN C.[Discount Line] = 2 THEN C5.LineValue
		WHEN C.[Discount Line] = 1 THEN C.[DiscountValue]
	END) AS [Global Discount]
INTO #InvoiceGrouping
FROM #Calc3 AS [C]
LEFT JOIN #CALC5 AS [C5] ON C5.LineUniqueID=C.LineUniqueID
GROUP BY 
		[TypeOfInvoice],
		[CustomerAutoId],
		[CustomerId],
		[CustomerName],
		[SiteId],
		[SiteAutoId],
		[Site],
		[PPMContractId],
		[JobId],
		JobAutoId,
		[Description],
		UserId,
		C.InvoiceType,
		C.[InvoiceGuid]
        --C.[VatRate],
        --C.[TaxCode],
        --C.TaxCodeId,
        --C.[NominalCode];

CREATE NONCLUSTERED INDEX IX_IG ON #InvoiceGrouping (InvoiceGuid);

SELECT
        IG.[InvoiceType], 
        BI.[AutoId], 
        BI.[UniqueId],
        BI.[ID],
        IG.[CustomerAutoId], 
        IG.[CustomerId],
        IG.[CustomerName], 
        BI.passedtoaccounts,
        IG.[SiteAutoId], 
        IG.[SiteId], 
        IG.[Site],
        IG.[PPMContractId], 
        IG.[Jobid], 
        IG.JobAutoId,
        BI.[Date], 
        IG.[Description],
        IG.UserId,
        BI.[OrderNo], 
        BI.[AccountNumber], 
        BI.[IsDraft], 
        BI.[Name], 
        BI.[Address1], 
        BI.[Address2], 
        BI.[Address3], 
        BI.[Address4], 
        BI.[Postcode],
        BI.[CreditNote], 
        BI.[Reason], 
        BI.CreditedInvoiceGuid AS [CreditedInvoiceGuid],
        COALESCE(IG.VatAmount,0) AS [vatvalue],
        COALESCE(IG.[ExcludingVat],0) AS [iNVOICEVALUE],
        COALESCE(IG.[IncludingVat],0) AS [TotalIncludingVat],
        COALESCE(IG.[DiscountValue],0) AS [TotalDiscountValue],
        COALESCE(IG.[ValueNoDiscount],0) AS [ValueNoDiscount],
        ROUND(CAST(100 AS FLOAT) - CAST( CASE WHEN COALESCE(IG.[ValueNoDiscount],0) <> 0 THEN
        ((COALESCE(IG.[ValueNoDiscount],0) - COALESCE(IG.[DiscountValue],0))/COALESCE(IG.[ValueNoDiscount],0))*100
        ELSE 0
        END AS Float),2)AS [TotalDiscountPercent],
        IG.[TypeOfInvoice],
        --IG.[vatrate],
        --IG.[taxcode],
        --IG.taxcodeid,
        --IG.[Nominalcode],
		COALESCE(CASE WHEN BI.CreditNote = 1 THEN -IG.[Global Discount] ELSE IG.[Global Discount] END,0) AS [Global Discount]
INTO #InvoiceCombined
FROM BaseInvoice AS [BI] 
LEFT JOIN #InvoiceGrouping AS [IG] ON BI.UniqueId = IG.InvoiceGuid;

CREATE NONCLUSTERED INDEX IX_IC ON #InvoiceCombined (CreditedInvoiceGuid);

SELECT 
	I.[InvoiceType], 
    I.[AutoId] AS [invoiceautoId], 
    I.[UniqueId],
	I.[ID] AS [InvoiceNumber],
	I.[CustomerAutoId], 
    I.[CustomerId],
    I.[CustomerName], 
    I.passedtoaccounts,
	I.[SiteAutoId], 
    I.[SiteId], 
    I.[Site] AS [SiteName],
	I.[PPMContractId], 
    I.[Jobid], 
    I.JobAutoId,
	I.[Date] AS [DateRaised], 
    I.[Description] AS [JobDescription],
    I.UserId,
	I.[OrderNo] AS [OrderNumber], 
    I.[AccountNumber], 
    I.[IsDraft], 
	I.[Name], 
    I.[Address1], 
    I.[Address2], 
    I.[Address3], 
    I.[Address4], 
    I.[Postcode],
	I.[CreditNote] AS [Creditnote], 
    I.[Reason] AS [CreditReason], 
    CI.[AutoId] AS [CreditId],
	I.CreditedInvoiceGuid AS [CreditedInvoiceGuid],
	CI.[ID] AS [CreditNumber], 
    CI.[IsDraft] AS [CreditIsDraft], 
    CI.[Date] AS [CreditDateRaised],
	ROUND(I.[vatvalue] , 2) AS vatvalue,
	ROUND(I.[iNVOICEVALUE] , 2) AS iNVOICEVALUE,
	ROUND(I.[TotalIncludingVat] , 2) AS TotalIncludingVat,
	ROUND(I.[TotalDiscountValue] , 2) AS TotalDiscountValue,
	ROUND(I.[ValueNoDiscount] , 2) AS ValueNoDiscount,
	CAST(I.[Global Discount] AS MONEY) AS [Global Discount],
	ROUND(I.[TotalDiscountPercent] , 2) AS TotalDiscountPercent,
    --I.[VatRate],
    --I.[TaxCode],
    --I.TaxCodeId,
    --I.[NominalCode],
    I.[TypeOfInvoice]
INTO #SalesInvoiceTotals
FROM #InvoiceCombined AS [I]
LEFT JOIN [BaseInvoice] AS [CI] ON I.[CreditedInvoiceGuid] = CI.[UniqueId];

CREATE NONCLUSTERED INDEX IX_SIT ON #SalesInvoiceTotals ([UniqueId]);


--------------#VisitCount------------------------------------------ 
SELECT 
JobAutoId,COUNT(*) AS [VISIT COUNT]  
INTO #Vcount
FROM JOBENG AS [JE]
GROUP BY JobAutoId

CREATE NONCLUSTERED INDEX IX_Vcount ON #Vcount(JobAutoId)

----------------------------main query-----------------------------------------------

SELECT 
	SIT.UniqueId AS [ID],
	CASE
		WHEN SIT.CreditNote = 0 
			THEN 'SI'  
		ELSE 'SC' 
		END AS [Type],
	CASE 
		WHEN COALESCE(S.AccountNumber,'') <>'' 
			THEN S.AccountNumber
		ELSE C.AccountNumber
		END AS [Account Reference],
	CASE 
		WHEN RSIL.nomcode IS NOT NULL 
			THEN RSIL.nomcode
		ELSE '4000'
	END AS [Nominal A/C Ref],
	CASE 
		WHEN QC.CostTypeID = 9 THEN QSORI.Code
		WHEN QC.CostTypeID = 5 THEN QP.Number
		WHEN CO.CostTypeID = 5 AND VC.[VISIT COUNT] = 1 THEN U.Reference
		ELSE U.Reference
	END AS [Department Code],
	CONVERT(VARCHAR,dbo.getlocaliseddate(SIT.DateRaised,@JGTimezone), 103) AS [Date],
	SIT.[InvoiceNumber] AS [Reference],
	CONCAT_WS('/',SIT.JobID,SIT.OrderNumber) AS [Details],     
	ABS(RSIL.LineValue) AS [Net Amount],
	RSIl.TaxCode AS [Tax Code],
	ABS(RSIL.VATValue) AS [Tax Amount],
	'' AS [Exchange Rate],
	LEFT(RSIL.Details,30) AS [Extra Reference]
FROM
	#SalesInvoiceTotals AS [SIT]
	LEFT JOIN #RoundedSalesInvoiceLines AS RSIL ON RSIL.InvoiceGuid = SIT.UniqueId
	LEFT JOIN Cost AS [CO] ON CO.InvoiceLineId = RSIL.invdetautoid
	LEFT JOIN QCost AS [QC] ON QC.InvoiceLineId = RSIL.invdetautoid
	LEFT JOIN ScheduleOfRateItem AS [QSORI] ON QSORI.ID= QC.ScheduleOfRatesItemId
	LEFT JOIN Part AS [QP] ON QP.StockItemID = QC.StockItemID
	LEFT JOIN Engineer AS [E] ON E.AutoLastId = CO.EngineerAutoId
	LEFT JOIN Users AS [U] ON U.EngineerId = E.AutoLastID 
	LEFT JOIN Customer AS [C] ON SIT.CustomerAutoID = C.AutoLastID
	LEFT JOIN [Contract] AS [S] ON SIT.SiteAutoID = S.AutoID
	LEFT JOIN #Vcount AS [VC] ON VC.JobAutoId = RSIL.JobAutoId
WHERE
	SIT.InvoiceValue <> 0
	AND SIT.PassedToAccounts = 0
	AND SIT.IsDraft = 0
ORDER BY 
	SIT.InvoiceNumber DESC
