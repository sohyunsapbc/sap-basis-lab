DECLARE @date datetime
SET @date = DATEADD(HOUR, -1, GETDATE())

EXECUTE master.dbo.xp_delete_file 0,N'D:\Backup',N'bak',@date,1
EXECUTE master.dbo.xp_delete_file 0,N'D:\Backup',N'ldf',@date,1
