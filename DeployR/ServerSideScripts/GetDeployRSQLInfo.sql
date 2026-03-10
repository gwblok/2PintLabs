SET NOCOUNT ON;

/*
Result Set 1: Database size summary (current database)
*/
SELECT
	DB_NAME() AS DatabaseName,
	CAST(SUM(df.size) * 8.0 / 1024 AS DECIMAL(18,2)) AS TotalSizeMB,
	CAST(SUM(CASE WHEN df.type_desc = 'ROWS' THEN FILEPROPERTY(df.name, 'SpaceUsed') ELSE 0 END) * 8.0 / 1024 AS DECIMAL(18,2)) AS UsedDataSpaceMB,
	CAST((
		SUM(CASE WHEN df.type_desc = 'ROWS' THEN df.size ELSE 0 END)
		- SUM(CASE WHEN df.type_desc = 'ROWS' THEN FILEPROPERTY(df.name, 'SpaceUsed') ELSE 0 END)
	) * 8.0 / 1024 AS DECIMAL(18,2)) AS FreeDataSpaceMB,
	CAST(SUM(CASE WHEN df.type_desc = 'LOG' THEN df.size ELSE 0 END) * 8.0 / 1024 AS DECIMAL(18,2)) AS LogSizeMB
FROM sys.database_files AS df;

/*
Result Set 2: Table size breakdown
*/
WITH TableSize AS
(
	SELECT
		s.name AS SchemaName,
		t.name AS TableName,
		SUM(ps.row_count) AS TableRowCount,
		SUM(ps.reserved_page_count) * 8.0 / 1024 AS ReservedMB,
		SUM(ps.used_page_count) * 8.0 / 1024 AS UsedMB,
		SUM(ps.in_row_data_page_count + ps.lob_used_page_count + ps.row_overflow_used_page_count) * 8.0 / 1024 AS DataMB,
		(SUM(ps.used_page_count) - SUM(ps.in_row_data_page_count + ps.lob_used_page_count + ps.row_overflow_used_page_count)) * 8.0 / 1024 AS IndexMB,
		(SUM(ps.reserved_page_count) - SUM(ps.used_page_count)) * 8.0 / 1024 AS UnusedMB
	FROM sys.tables AS t
	INNER JOIN sys.schemas AS s
		ON t.schema_id = s.schema_id
	INNER JOIN sys.dm_db_partition_stats AS ps
		ON t.object_id = ps.object_id
	GROUP BY
		s.name,
		t.name
)
SELECT
	SchemaName,
	TableName,
	TableRowCount,
	CAST(ReservedMB AS DECIMAL(18,2)) AS ReservedMB,
	CAST(UsedMB AS DECIMAL(18,2)) AS UsedMB,
	CAST(DataMB AS DECIMAL(18,2)) AS DataMB,
	CAST(IndexMB AS DECIMAL(18,2)) AS IndexMB,
	CAST(UnusedMB AS DECIMAL(18,2)) AS UnusedMB
FROM TableSize
ORDER BY ReservedMB DESC, SchemaName, TableName;
