


/*What does the script look like*/
CREATE EVENT SESSION [MySessionOf1Minute]
   ON SERVER
   ADD EVENT sqlserver.rpc_completed
   (ACTION (
              sqlserver.client_app_name,
              sqlserver.client_hostname,
              sqlserver.session_id
           )
    WHERE ([duration] > (3000000))
   ),
   ADD EVENT sqlserver.sql_batch_completed
   (ACTION (
              sqlserver.client_app_name,
              sqlserver.client_hostname,
              sqlserver.session_id
           )
    WHERE ([duration] > (3000000))
   )
   ADD TARGET package0.event_file
   (SET filename = N'MyMinuteSession', max_file_size = (50)),
   ADD TARGET package0.ring_buffer
   WITH (
           MAX_MEMORY = 4096KB,
           EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
           MAX_DISPATCH_LATENCY = 30 SECONDS,
           MAX_EVENT_SIZE = 0KB,
           MEMORY_PARTITION_MODE = NONE,
           TRACK_CAUSALITY = ON,
           STARTUP_STATE = ON --,
                              --MAX_DURATION=60 SECONDS
        );
GO

/*Start it*/
ALTER EVENT SESSION [MySessionOf1Minute]
   ON SERVER STATE = START;
GO

/*Stop it (when you want to, or await the MAX_DURATION*/
ALTER EVENT SESSION [MySessionOf1Minute]
   ON SERVER STATE = STOP;
GO

/* Create one without the max_duration we can use today*/
CREATE EVENT SESSION [MySession]
   ON SERVER
   ADD EVENT sqlserver.rpc_completed
   (ACTION (
              sqlserver.client_app_name,
              sqlserver.client_hostname,
              sqlserver.session_id
           )
   --WHERE ([duration] > (3000000))              /*3 seconds.., or any other filter you want..*/
   ),
   ADD EVENT sqlserver.sql_batch_completed
   (ACTION (
              sqlserver.client_app_name,
              sqlserver.client_hostname,
              sqlserver.session_id
           )
   --WHERE ([duration] > (3000000))
   )
   ADD TARGET package0.event_file
   (SET filename = N'MySession', max_file_size = (50)),
   ADD TARGET package0.ring_buffer
   WITH (
           MAX_MEMORY = 4096KB,
           EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
           MAX_DISPATCH_LATENCY = 30 SECONDS,
           MAX_EVENT_SIZE = 0KB,
           MEMORY_PARTITION_MODE = NONE,
           TRACK_CAUSALITY = ON,
           STARTUP_STATE = ON
        );
GO

ALTER EVENT SESSION [MySession]
   ON SERVER STATE = START;
GO

/* Start live feed*/

USE StackOverflow2013;
GO

-- batch completes
EXEC dbo.GetUserInformation @UserId = -1; -- int

--rpc completed in VSCode

/* Show how stuff works within the GUI*/

/* How can we read this more automatically?*/
/*Reading from an event file*/
SELECT
     event_data = CONVERT(XML, event_data),
     object_name,
     file_name,
     file_offset,
     timestamp_utc
FROM sys.fn_xe_file_target_read_file(N'MySession*.xel', NULL, NULL, NULL);


/*Great! Some XML.. , we should be able to retrieve some details from that..*/
/*Let's spit this output into a temp table, so we can work on the data*/


DROP TABLE IF EXISTS #RetrievedData;

SELECT
     object_name,
     event_data = CONVERT(XML, event_data),
     file_name,
     file_offset,
     timestamp_utc
INTO #RetrievedData
FROM sys.fn_xe_file_target_read_file(N'MySession*.xel', NULL, NULL, NULL);

SELECT
     ts = rd.event_data.value(N'(event/@timestamp)[1]', N'datetime'),
     batch_text = rd.event_data.value(
                                        N'(event/data[@name="batch_text"]/value)[1]',
                                        N'nvarchar(max)'
                                     ),
     statement = rd.event_data.value(
                                       N'(event/data[@name="statement"]/value)[1]',
                                       N'nvarchar(max)'
                                    ),
     spid = rd.event_data.value(
                                  N'(event/action[@name="session_id"]/value)[1]',
                                  N'int'
                               ),
     duration = rd.event_data.value(
                                      N'(event/data[@name="duration"]/value)[1]',
                                      N'bigint'
                                   ),
     dxoc.description AS duration_description /*some might contain other duration units*/
FROM #RetrievedData AS rd
     LEFT JOIN sys.dm_xe_object_columns AS dxoc ON dxoc.name = 'duration'
                                                   AND dxoc.object_name = rd.object_name;


DROP TABLE IF EXISTS #RetrievedData;

GO

/*But what if we would like to see the data from the ring_buffer? We might need it for SQL Server 2008*/
/*Oh, don't forget to enable your trace first :)*/

WITH cte
AS (SELECT ed = CONVERT(XML, target_data)
    FROM   sys.dm_xe_session_targets xet
           INNER JOIN sys.dm_xe_sessions xe ON xe.[address] = xet.event_session_address
    WHERE  xe.name = N'MySession'
           AND xet.target_name = N'ring_buffer')
SELECT event_data = x.ed.query('.')
FROM   cte
       CROSS APPLY cte.ed.nodes(N'RingBufferTarget/event') AS x(ed);


/*Again a very nice XML*/
DROP TABLE IF EXISTS #RetrievedData;

WITH cte
AS (SELECT ed = CONVERT(XML, target_data)
    FROM   sys.dm_xe_session_targets xet
           INNER JOIN sys.dm_xe_sessions xe ON xe.[address] = xet.event_session_address
    WHERE  xe.name = N'MySession'
           AND xet.target_name = N'ring_buffer')
SELECT event_data = x.ed.query('.')
INTO   #RetrievedData
FROM   cte
       CROSS APPLY cte.ed.nodes(N'RingBufferTarget/event') AS x(ed);

SELECT
     ts = event_data.value(N'(event/@timestamp)[1]', N'datetime'),
     batch_text = event_data.value(
                                     N'(event/data[@name="batch_text"]/value)[1]',
                                     N'nvarchar(max)'
                                  ),
     statement = event_data.value(
                                    N'(event/data[@name="statement"]/value)[1]',
                                    N'nvarchar(max)'
                                 ),
     spid = event_data.value(
                               N'(event/action[@name="session_id"]/value)[1]',
                               N'int'
                            ),
     duration = event_data.value(
                                   N'(event/data[@name="duration"]/value)[1]',
                                   N'bigint'
                                ),
     event_name = event_data.value(N'(event/@name)[1]', N'nvarchar(max)'),
     dxoc.description AS duration_description /*some might contain other duration units*/
FROM #RetrievedData AS rd
     LEFT JOIN sys.dm_xe_object_columns AS dxoc ON dxoc.name = 'duration'
                                                   AND dxoc.object_name = event_data.value(
                                                                                             N'(event/@name)[1]',
                                                                                             N'nvarchar(max)'
                                                                                          );
DROP TABLE IF EXISTS #RetrievedData;




/* When time permits*/
/*

Will create an event which will keep track of the Deadlocks and query's which will go over the configured threshold.

/*to configure threshold, minimum is 5*/
EXEC sp_configure 'blocked process threshold', '5';
RECONFIGURE
GO

https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/blocked-process-threshold-server-configuration-option?view=sql-server-ver16

*/

CREATE EVENT SESSION [blocked_process]
   ON SERVER
   ADD EVENT sqlserver.blocked_process_report
   (ACTION (
              sqlserver.client_app_name,
              sqlserver.client_hostname,
              sqlserver.database_name
           )
   ),
   ADD EVENT sqlserver.xml_deadlock_report
   (ACTION (
              sqlserver.client_app_name,
              sqlserver.client_hostname,
              sqlserver.database_name
           )
   )
   ADD TARGET package0.event_file
   (SET filename = N'blocked_process', max_file_size = (100))
   WITH (
           MAX_MEMORY = 4096KB,
           EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
           MAX_DISPATCH_LATENCY = 5 SECONDS,
           MAX_EVENT_SIZE = 0KB,
           MEMORY_PARTITION_MODE = NONE,
           TRACK_CAUSALITY = OFF,
           STARTUP_STATE = ON
        );
GO


ALTER EVENT SESSION [blocked_process]
   ON SERVER STATE = START;
GO


-- How to find blocking issues
--Session 1:

USE StackOverflow2013;
GO

BEGIN TRAN;
UPDATE dbo.Users
SET    Age = 1
WHERE  Id = -1;
--ROLLBACK TRAN
-- Session 2:
BEGIN TRAN;
UPDATE dbo.Users
SET    Age = 0
WHERE  Id = -1;
--ROLLBACK TRAN

/* Find which deprecated features are in use*/
CREATE EVENT SESSION [DeprecatedFeatures]
   ON SERVER
   ADD EVENT sqlserver.deprecation_announcement
   (ACTION (
              sqlserver.sql_text
           )
   ),
   ADD EVENT sqlserver.deprecation_final_support
   (ACTION (
              sqlserver.sql_text
           )
   )
   WITH (
           MAX_MEMORY = 4096KB,
           EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
           MAX_DISPATCH_LATENCY = 30 SECONDS,
           MAX_EVENT_SIZE = 0KB,
           MEMORY_PARTITION_MODE = NONE,
           TRACK_CAUSALITY = OFF,
           STARTUP_STATE = OFF
        );
GO

ALTER EVENT SESSION [DeprecatedFeatures]
   ON SERVER STATE = START;
GO

/* run something deprecated*/
DECLARE @var TABLE
(
   Id INT,
   Value TEXT
);

CREATE EVENT SESSION [query_antipatterns]
   ON SERVER
   ADD EVENT sqlserver.query_antipattern
   (ACTION (
              sqlserver.client_app_name,
              sqlserver.plan_handle,
              sqlserver.query_hash,
              sqlserver.query_plan_hash,
              sqlserver.sql_text
           )
   )
   ADD TARGET package0.event_file
   (SET filename = N'query_antipatterns', max_file_size = (50))
GO

ALTER EVENT SESSION [query_antipatterns]
   ON SERVER STATE = START;
GO

/*Make sure implicit casting occurs*/
SELECT *
FROM dbo.Users AS b
WHERE b.UserIdVC = 164
OPTION (RECOMPILE);

/* Track SQL modules*/
CREATE EVENT SESSION [CountExecutions]
   ON SERVER
   ADD EVENT sqlserver.module_end
   (WHERE ([object_id] > (0)))
   ADD TARGET package0.histogram
   (SET filtering_event_name = N'sqlserver.module_end', slots = (10000), source = N'object_id', source_type = (0))
   WITH (
           MAX_MEMORY = 4096KB,
           EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
           MAX_DISPATCH_LATENCY = 30 SECONDS,
           MAX_EVENT_SIZE = 0KB,
           MEMORY_PARTITION_MODE = NONE,
           TRACK_CAUSALITY = OFF,
           STARTUP_STATE = ON
        );
GO


ALTER EVENT SESSION [CountExecutions]
   ON SERVER STATE = START;
GO


EXEC StackOverflow2013.dbo.GetUserBasics @UserId = 345 -- int




/* cleanup demo*/
IF EXISTS (
             SELECT 1
             FROM   sys.server_event_sessions
             WHERE  name = N'MySession'
          )
BEGIN
   DROP EVENT SESSION [MySession] ON SERVER;
END;
GO

IF EXISTS (
             SELECT 1
             FROM   sys.server_event_sessions
             WHERE  name = N'MySessionOf1Minute'
          )
BEGIN
   DROP EVENT SESSION [MySessionOf1Minute] ON SERVER;
END;
GO

IF EXISTS (
             SELECT 1
             FROM   sys.server_event_sessions
             WHERE  name = N'blocked_process'
          )
BEGIN
   DROP EVENT SESSION [blocked_process] ON SERVER;
END;
GO


IF EXISTS (
             SELECT 1
             FROM   sys.server_event_sessions
             WHERE  name = N'DeprecatedFeatures'
          )
BEGIN
   DROP EVENT SESSION [DeprecatedFeatures] ON SERVER;
END;
GO

IF EXISTS (
             SELECT 1
             FROM   sys.server_event_sessions
             WHERE  name = N'query_antipatterns'
          )
BEGIN
   DROP EVENT SESSION [query_antipatterns] ON SERVER;
END;
GO

IF EXISTS (
             SELECT 1
             FROM   sys.server_event_sessions
             WHERE  name = N'CountExecutions'
          )
BEGIN
   DROP EVENT SESSION [CountExecutions] ON SERVER;
END;
GO







