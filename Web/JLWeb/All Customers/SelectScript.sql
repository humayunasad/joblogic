--------------------------------------------------------------------#SalesInvoicePaymentStatus--------------------------------------------------
    SELECT 
        BI.Uniqueid,
        BI.Creditnote,
        BI.[ID],
        BI.CreditedInvoiceGuid
INTO #ExcludingDrafts_PS
FROM BaseInvoice AS [BI] 
WHERE 
     BI.IsDraft = 0;
CREATE NONCLUSTERED INDEX IX_ExcludingDrafts_PS ON #ExcludingDrafts_PS (UNIQUEID,CreditedInvoiceGuid);
SELECT 
		[InvoiceGuid],
        [Qty],
        [Price], 
        [Discount_Amount], 
        [Discount_Percentage], 
        Taxcodes.[Value] AS [vATrATE],
		BI.creditnote AS [Credit]
INTO #InvoiceLineUnion_PS
FROM [Invdets]
	INNER JOIN #ExcludingDrafts_PS AS [BI] ON Invdets.InvoiceGuid = BI.uniqueid
	INNER JOIN Invoice AS [I] ON Invdets.InvoiceGuid = I.UniqueID
	INNER JOIN Job AS [J] ON I.JobAutoId = J.AutoId -- Removes Bad Data
	LEFT JOIN TaxCodes ON invdets.taxcodeid = taxcodes.uniqueid

UNION ALL

SELECT
		[InvoiceId], 
        [Quantity] AS [Qty], 
        [PricePerUnit] AS [Price], 
        [Discount_Amount], 
        [Discount_Percentage],
        Taxcodes.value as [vATrATE],
		BI.creditnote  as [Credit]
FROM [PPMContract_InvoiceLines]
	INNER JOIN #ExcludingDrafts_PS AS [BI] ON PPMContract_InvoiceLines.InvoiceId = BI.uniqueid
	LEFT JOIN taxcodes on [PPMContract_InvoiceLines].taxcodeid = taxcodes.uniqueid

UNION ALL
	
SELECT
        [InvoiceGuid],
        [Qty],
        [Price],
        [Discount_Amount],
        [Discount_Percentage],
        Taxcodes.[Value] AS [vATrATE],
        BI.creditnote AS [Credit]
FROM [CustomerGrouped_InvoiceLine]
	INNER JOIN #ExcludingDrafts_PS AS [BI] ON CustomerGrouped_InvoiceLine.InvoiceGuid = BI.uniqueid
	LEFT JOIN TaxCodes ON [CustomerGrouped_InvoiceLine].taxcodeid = taxcodes.uniqueid;

CREATE NONCLUSTERED INDEX IX_InvoiceLineUnion_PS ON #InvoiceLineUnion_PS (INVOICEGUID);

SELECT
		il.[InvoiceGuid],
		ROUND(CAST(CASE 
			WHEN (il.[Discount_Amount] IS NOT NULL) THEN round((il.[Qty] * il.[Price]) - il.[Discount_Amount],2)
			WHEN (il.[Discount_Percentage] IS NOT NULL) THEN round((il.[Qty] * il.[Price]) * (1 - (il.[Discount_Percentage] / 100)),2)
			ELSE ROUND(CAST(il.[Qty] * il.[Price] AS MONEY), 2) 
		END AS money),2) AS [LineValue],
		CAST((CASE 
			WHEN (il.[Discount_Amount] IS NOT NULL) THEN round(((il.[Qty] * il.[Price]) - il.[Discount_Amount]) * ISNULL(il.[VatRate], 0) / 100,2)
			WHEN (il.[Discount_Percentage] IS NOT NULL) THEN round((il.[Qty] * il.[Price]) * (1 - (il.[Discount_Percentage] / 100)) * ISNULL(il.[VatRate], 0) / 100,2)
			ELSE ROUND(CAST(il.[Qty] * il.[Price] * ISNULL(il.[VatRate], 0) / 100 AS money), 2)
		END) AS money) AS [VATValue],
		[Credit]
INTO #CALC_PS
FROM #InvoiceLineUnion_PS il;

CREATE NONCLUSTERED INDEX IX_CALC_PS ON #CALC_PS(INVOICEGUID);

SELECT
	C.[InvoiceGuid]
	,CASE C.[Credit] WHEN 1 THEN -(C.[LineValue] + C.[VATValue]) ELSE (C.[LineValue] + C.[VATValue]) END AS [IncludingVat]
INTO #LinesCalculated_PS
 FROM #CALC_PS AS [C];
 CREATE NONCLUSTERED INDEX IX_LinesCalculated_PS ON #LinesCalculated_PS(INVOICEGUID);

SELECT 
		[InvoiceGuid],
		SUM(COALESCE([IncludingVat],0)) AS [IncludingVat]
INTO #InvoiceGrouping_PS
FROM #LinesCalculated_PS
GROUP BY [InvoiceGuid];
CREATE NONCLUSTERED INDEX IX_InvoiceGrouping_PS ON #InvoiceGrouping_PS(INVOICEGUID);

SELECT 
    bi.[UniqueId],
	bi.[ID] AS [InvoiceNumber],
	bi.CreditedInvoiceGuid AS [CreditedInvoiceGuid],
    COALESCE(ic.[IncludingVat],0)  AS [TotalIncludingVat],
    BI.CreditNote
INTO #TotalCalc_PS
FROM #ExcludingDrafts_PS bi
	LEFT JOIN [#InvoiceGrouping_PS] ic ON ic.[InvoiceGuid] = bi.[UniqueId];
CREATE NONCLUSTERED INDEX IX_TotalCalc_PS ON #TotalCalc_PS(UNIQUEID,CREDITEDINVOICEGUID);

SELECT 
		InvoiceGuid,
		SUM(COALESCE(Amount,0)) AS [Amount]
INTO #TotalInvoicePayments_PS
FROM InvoicePayments
GROUP BY InvoiceGuid

UNION ALL

SELECT
	 	PPMContract_InvoicePayments.PPMContract_invoiceID AS [InvoiceGuid],
		SUM(COALESCE(Amount,0)) AS [Amount]
FROM PPMContract_InvoicePayments 
GROUP BY PPMContract_invoiceID

UNION ALL

SELECT 
		InvoiceGuid,
		SUM(COALESCE(Amount,0)) AS [Amount]
	 FROM CustomerGrouped_InvoicePayment
	 GROUP BY InvoiceGuid;
CREATE NONCLUSTERED INDEX IX_TotalInvoicePayments_PS ON #TotalInvoicePayments_PS(INVOICEGUID);

 SELECT
 SIT.CreditedInvoiceGuid AS [CreditedInvoiceGuid],
 SUM(COALESCE(SIT.TotalIncludingVAT,0)) AS [TotalCredit]
INTO 
	#Credited_PS
FROM [#TotalCalc_PS] AS [SIT]
WHERE  SIT.CreditNote = 1
GROUP BY CreditedInvoiceGuid;
CREATE NONCLUSTERED INDEX IX_Credited_PS ON #Credited_PS(CREDITEDINVOICEGUID);

 SELECT
	BI.ID AS InvoiceNumber,
	0 AS TotalIncludingVAT,
	COALESCE(Cred.[TotalCredit], 0) AS [TotalCredit],
	BI.UniqueId AS [InvoiceGuid]
INTO #InvoiceAndCreditsGrouped_PS
FROM [dbo].BaseInvoice AS [BI]
	LEFT JOIN #Credited_PS AS [Cred] ON BI.UniqueId = Cred.[CreditedInvoiceGuid]
WHERE [BI].IsDraft = 0 AND [BI].CreditNote = 0

UNION ALL

SELECT 
		SIT.InvoiceNumber,
		SIT.TotalIncludingVAT,
		0 AS [TotalCredit],
		SIT.UniqueID
FROM #TotalCalc_PS AS [SIT]
WHERE SIT.CreditNote = 0;
CREATE NONCLUSTERED INDEX IX_InvoiceAndCreditsGrouped_PS ON #InvoiceAndCreditsGrouped_PS(INVOICEGUID);

SELECT
	[IACG].InvoiceNumber AS [ID],
	SUM([IACG].TotalIncludingVAT) AS [Invoice Total],
	SUM([IACG].TotalIncludingVAT + [IACG].[TotalCredit]) AS [Invoice Total Inc Credits],
	COALESCE(TIP.Amount,0) AS [Paid],
	CASE 
		WHEN SUM([IACG].TotalIncludingVAT + [IACG].[TotalCredit]) <= COALESCE(TIP.Amount,0) 
			THEN 'Paid'
		WHEN COALESCE(TIP.Amount,0) <= 0
			THEN 'Unpaid'
		WHEN SUM([IACG].TotalIncludingVAT + [IACG].[TotalCredit]) > COALESCE(TIP.Amount,0) 
			THEN 'Partially Paid'	
			END AS [Payment Status],
	[IACG].InvoiceGuid
INTO #SalesInvoicePaymentStatus
FROM #InvoiceAndCreditsGrouped_PS AS [IACG]
	LEFT JOIN #TotalInvoicePayments_PS AS [TIP] ON [IACG].[InvoiceGuid] = TIP.InvoiceGuid
GROUP BY 
    [IACG].InvoiceNumber, 
    TIP.Amount, 
    [IACG].InvoiceGuid
CREATE NONCLUSTERED INDEX IX_SalesInvoicePaymentStatus ON #SalesInvoicePaymentStatus(INVOICEGUID);
------------------------------------------------------------------------------------------------------
-------------------------------------------------#SalesInvoiceTotals---------------------------------------------------------------------------------
SELECT 
	0 AS [InvoiceType],
	C.[AutoLastId] AS [CustomerAutoId], C.[ID] AS [CustomerId], C.[Name] AS [CustomerName],
	S.[AutoId] AS [SiteAutoId], S.[ID] AS [SiteId], S.[Site],
	J.[id] AS [JobId], NULL AS [PPMContractId], J.[ID] AS [id], J.AutoId AS JobAutoId,
	J.[Description],userid, 'S' AS [TypeOfInvoice],
	BI.UniqueId AS [InvoiceGuid],
	Il.[Qty],
	Il.[Price], 
	Il.[Discount_Amount], 
	Il.[Discount_Percentage], 
	Il.taxcodeid,
	BI.creditnote AS [Credit],
	Il.NominalCodeId,
	Il.CreatedAt,
	Il.UniqueId AS [LineUniqueID],
	CASE
			WHEN [Il].Discount_Amount IS NOT NULL AND [Il].Price=0 THEN 1 
			WHEN [Il].Discount_Percentage IS NOT NULL AND [Il].Price=0 THEN 2 
			ELSE 0 
	END AS [Discount Line]
INTO #InvoiceLineUnion
FROM [Invoice] AS [I]
	INNER JOIN BaseInvoice AS [BI] ON I.UniqueId = BI.uniqueid
	INNER JOIN [Job] AS [J] ON J.[AutoId] = I.[JobAutoId]
	LEFT JOIN Customer AS [C] ON C.[AutoLastID] = J.[CustomerAutoId]
	LEFT JOIN [Contract] AS [S] ON S.[AutoId] = J.[SiteAutoId]
	LEFT JOIN Invdets AS [Il] ON I.UniqueId = Il.InvoiceGuid
	LEFT JOIN Invdets AS [CR] ON CR.AutoID = Il.CreditedInvoiceLineId
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
	 NULL AS userid, 
	 'P' AS [TypeOfInvoice],
	 BI.UniqueId AS [InvoiceGuid],
	 IL.[Quantity] AS [Qty], 
	 IL.[PricePerUnit] AS [Price], 
	 IL.[Discount_Amount], 
	 IL.[Discount_Percentage],
	 Il.taxcodeid, 
	 BI.creditnote  AS [Credit],
	 Il.NominalCodeId,
	 Il.CreatedAt,
	 Il.UniqueId AS [LineUniqueID],
	NULL AS [Discount Line]
FROM [PPMContract_Invoices] AS [I]
	INNER JOIN BaseInvoice AS [BI] ON I.UniqueId = BI.uniqueid
	LEFT JOIN [PPMContract] AS [P] ON P.[UniqueId] = I.[PPMContractId]
	LEFT JOIN Customer AS [C] ON C.[AutoLastID] = P.[CustomerAutoId]
	LEFT JOIN [Contract] AS [S] ON s.[AutoId] = p.[SiteAutoId]
	LEFT JOIN [PPMContract_InvoiceLines] AS [Il] ON I.UniqueId = Il.InvoiceId
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
	 NULL AS [userid],  
	 'C' AS [TypeOfInvoice],
	 BI.UniqueId AS [InvoiceGuid],
	 IL.[Qty],
	 IL.[Price],
	 IL.[Discount_Amount],
	 IL.[Discount_Percentage],
	 Il.taxcodeid, 
	 BI.creditnote AS [Credit],
	 Il.NominalCodeId,
	 Il.CreatedAt,
	 Il.UniqueId AS [LineUniqueID],
	NULL AS [Discount Line]
FROM [CustomerGrouped_Invoice] AS [I]
	INNER JOIN baseinvoice AS [BI] ON I.UniqueId = BI.uniqueid   
	LEFT JOIN Customer AS [C] ON C.[AutoLastID] = I.[CustomerAutoId]
	LEFT JOIN [CustomerGrouped_InvoiceLine] AS [Il] ON I.UniqueId = Il.InvoiceGuid;
		   
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
		COALESCE(il.[Qty] * il.[Price],0)  AS [QTimesP],
		IL.[Discount_Percentage],
		IL.[Discount_Amount],
        TC.[Value]  AS [vatrate],
        TC.Code AS [taxcode],
        TC.UniqueId AS taxcodeid,
        NC.[Code] AS [Nominalcode],
		IL.LineUniqueID,
		IL.[Discount Line]
INTO #Calc
FROM #InvoiceLineUnion AS [IL]
	LEFT JOIN TaxCodes AS [TC] ON IL.taxcodeid = TC.uniqueid
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
		C.QTimesP  AS [LineValueNoDiscount],
        C.[vatrate],
        C.[taxcode],
        C.taxcodeid,
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
		[Jobid], 
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
		[Jobid], 
		JobAutoId,
		[Description], 
		UserId,
		C.InvoiceType,
		C.[InvoiceGuid]
        --C.[vatrate],
        --C.[taxcode],
        --C.taxcodeid,
        --C.[Nominalcode];

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
        IG.userid,
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
        COALESCE(IG.[IncludingVat],0)  AS [TotalIncludingVat],
        COALESCE(IG.[DiscountValue],0)  AS [TotalDiscountValue],
        COALESCE(IG.[ValueNoDiscount],0)  AS [ValueNoDiscount],
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
	INNER JOIN #InvoiceGrouping AS [IG] ON BI.UniqueId = IG.InvoiceGuid;

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
    I.userid,
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
    --I.[vatrate],
    --I.[taxcode],
    --I.taxcodeid,
    --I.[Nominalcode],
    I.[TypeOfInvoice]
INTO #SalesInvoiceTotals
FROM #InvoiceCombined AS [I]
	LEFT JOIN [BaseInvoice] AS [CI] ON I.[CreditedInvoiceGuid] = CI.[UniqueId];

CREATE NONCLUSTERED INDEX IX_SIT ON #SalesInvoiceTotals (JobAutoId);

----------------------Total Remaining Balance-------------------------------------------------------------

SELECT
	SIT.CustomerAutoId,
	COALESCE(SUM(IPS.[Invoice Total Inc Credits] - IPS.Paid),0) AS [Balance]
	INTO #TotalReceivable
FROM #SalesInvoiceTotals SIT
	LEFT JOIN #SalesInvoicePaymentStatus IPS ON SIT.UniqueId = IPS.InvoiceGuid
GROUP BY SIT.CustomerAutoId

-----------------------Standard and Customer Grouped Incoices Remaining Balance----------------------------

SELECT
	SIT.CustomerAutoId,
	COALESCE(SUM(IPS.[Invoice Total Inc Credits] - IPS.Paid), 0) AS [ExPPMBalance]
	INTO #TotalReceivableExPPM
FROM #SalesInvoiceTotals SIT
	LEFT JOIN #SalesInvoicePaymentStatus IPS ON SIT.UniqueId = IPS.InvoiceGuid
WHERE SIT.TypeOfInvoice <> 'P'
GROUP BY SIT.CustomerAutoId

-------------------------PPM Invoices Remaining Balance-----------------------------------------------------

SELECT
	TR.CustomerAutoId,
	TR.Balance - TRE.ExPPMBalance AS [PPMBalance]
	INTO #TotalReceivablePPM
FROM #TotalReceivable TR
	LEFT JOIN #TotalReceivableExPPM TRE ON TRE.CustomerAutoId = TR.CustomerAutoId

--------------------------All Customers from JLWeb------------------------------------------------------------

SELECT
	TL.LevelId,
	STRING_AGG(T.Title, ', ')  AS [TG]
INTO #CUSTAG
FROM TagLevel AS [TL]
	LEFT JOIN Tag AS [T] ON TL.TagId = T.uniqueid
WHERE EntityType =1
GROUP BY TL.LevelId;
CREATE NONCLUSTERED INDEX IX_CUSTAG ON #CUSTAG (LEVELID);
--------------------------------------------------------------------------------------------------------------

SELECT value, AutoLastID
INTO #TMP1
FROM Customer  
    CROSS APPLY STRING_SPLIT(JobTypeIds,',')

SELECT
	C.autolastid,
	String_agg(JCT.[Description],', ') AS [Desc]
INTO #TMP2
FROM Customer AS C
	LEFT JOIN #TMP1 AS TMP1 ON tmp1.AutoLastID=C.AutoLastID
	LEFT JOIN Jobctl AS JCT ON JCT.AutoID=TMP1.[value]
GROUP BY C.AutoLastID

SELECT value, AutoLastID
INTO #TMP3
FROM Customer  
    CROSS APPLY STRING_SPLIT(JobCategoryIds,',')

SELECT
	C.AutoLastID,
	String_agg(JC.[Description],', ') AS [Desc]
INTO #TMP4
FROM Customer AS C
	INNER JOIN #TMP3 AS TMP3 ON TMP3.AutoLastID=C.AutoLastID
	LEFT JOIN JobCategory AS JC ON JC.AutoID=TMP3.[value]
GROUP BY C.AutoLastID
--------------------------------------------------------------------------------------------------------------

SELECT
	C.ID AS [ID],
	C.[Name],
	U.FullName AS [Customer Account Manager],
	C.Address1 AS [Address 1],
	C.Address2 AS [Address 2],
	C.Address3 AS [Address 3],
	C.Address4 AS [Address 4], 
	C.Postcode ,
	C.customreference AS [Reference],
	CT.[Description] AS [Customer Type],
	C.Contact,
	C.Telephone,
	C.EmailAddress AS [Email Address],
	C.VatNumber AS [VAT Number],
	C.AccountNumber AS [Account Number],
	SR.[Description] AS [Selling Rate],
	C.Warning1Used ,
	C.Warning1Comments,
	C.Warning2Used,
	C.Warning2Comments,
	C.Warning3Used,
	C.Warning3Comments,
	~Inactive AS [Active],
    CTAG.TG AS [Customer Tags],
	COALESCE(TRB.Balance,0) AS [Total Receivable Balance],
	COALESCE(TRBEP.ExPPMBalance,0) AS [Standard/CG Receivable Balance],
	COALESCE(TRBPPM.PPMBalance,0) AS [PPM Receivable Balance],
	C.JobTypeCategoryDescription [Customer Job Type & Job Category - Description],
	SRL.[Description] AS [Default SOR Library],
	CASE 
			WHEN SRCL.Uplift > 0 THEN CONCAT('Uplift','-',SRCL.Uplift,'%')
			WHEN SRCL.Discount > 0  THEN  CONCAT('Discount','-',SRCL.Discount,'%')
			ELSE NULL
	END AS [Uplift/Discount % ],
	FCL.[Description] AS [Fault Code Library],
	CASE 
				WHEN C.ImpactJobPriority=1 THEN 'Yes'
				ELSE 'No'
		END AS [Impact Job Priority (Yes/No)],
	JTA.[Desc] AS [Job Types Assigned],
	JCA.[Desc] AS [Job Categories Assigned],
	CASE 
			WHEN C.ShowInBO=0 THEN 'No' 
			ELSE 'Yes'
		END AS [Filter in Back Office (Yes/No)],
	CASE 
			WHEN C.ShowInPortal=0 THEN 'No' 
			ELSE 'Yes'
		END AS [Filter in Customer Portal (Yes/No)],
	CASE 
			WHEN C.ShowInMobile=0 THEN 'No' 
			ELSE 'Yes'
		END AS [Filter in Mobile App (Yes/No)]
		
		
FROM Customer AS [C] 
	LEFT JOIN CustomerTypes AS [CT] ON CT.CustTypeID = C.CustTypeID
	LEFT JOIN SellingRates AS [SR] ON SR.ID = C.SellingRateID
	LEFT JOIN Users AS [U] ON U.UserId=C.AccountManagerID
	LEFT JOIN #CUSTAG AS [CTAG] ON CTAG.LevelId=C.UniqueId
	LEFT JOIN #TotalReceivable AS [TRB] ON TRB.CustomerAutoId = C.AutoLastID
	LEFT JOIN #TotalReceivableExPPM AS [TRBEP] ON TRBEP.CustomerAutoId = C.AutoLastID
	LEFT JOIN #TotalReceivablePPM AS [TRBPPM] ON TRBPPM.CustomerAutoId = C.AutoLastID
	LEFT JOIN #TMP2 AS [JTA] ON JTA.AutoLastID=C.AutoLastID
	LEFT JOIN #TMP4 AS [JCA] ON JCA.AutoLastID=C.AutoLastID
	LEFT JOIN ScheduleOfRateCustomerLink AS [SRCL] ON C.AutoLastID=SRCL.CustomerId AND SRCL.IsDefault=1
	LEFT JOIN ScheduleOfRateLibrary AS [SRL] ON SRL.Id=SRCL.LibraryId
	LEFT JOIN FaultCodeLibrary AS [FCL] ON FCL.AutoId=C.FCLibraryAutoId
