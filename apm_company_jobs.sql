
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
            job_name => '"APM_COMPANY"."UPDATE_SALARY"',
            job_type => 'PLSQL_BLOCK',
            job_action => 'begin
EXECUTE IMMEDIATE q''{

UPDATE apm_employees
SET salary = salary + 100
WHERE hire_date = add_months (trunc(sysdate), -240)

}'';
end;',
            number_of_arguments => 0,
            start_date => NULL,
            repeat_interval => 'FREQ=DAILY',
            end_date => NULL,
            enabled => FALSE,
            auto_drop => FALSE,
            comments => '');

         
     
 
    DBMS_SCHEDULER.SET_ATTRIBUTE( 
             name => '"APM_COMPANY"."UPDATE_SALARY"', 
             attribute => 'store_output', value => TRUE);
    DBMS_SCHEDULER.SET_ATTRIBUTE( 
             name => '"APM_COMPANY"."UPDATE_SALARY"', 
             attribute => 'logging_level', value => DBMS_SCHEDULER.LOGGING_OFF);
      
   
  
    
    DBMS_SCHEDULER.enable(
             name => '"APM_COMPANY"."UPDATE_SALARY"');
END;


BEGIN
    DBMS_SCHEDULER.create_program(
        program_name => 'APM_COMPANY.UPDATE_CURRENT_SALARY',
        program_action => 'begin
EXECUTE IMMEDIATE q''{

UPDATE apm_salary
SET    actual_salary  = (SELECT salary
                FROM   apm_employees
                WHERE  apm_employees.emp_id = apm_salary.emp_id)

}'';
end;',
        program_type => 'PLSQL_BLOCK',
        number_of_arguments => 0,
        comments => NULL,
        enabled => FALSE);



  

    DBMS_SCHEDULER.ENABLE(name=>'APM_COMPANY.UPDATE_CURRENT_SALARY');    

END;


BEGIN
    DBMS_SCHEDULER.CREATE_SCHEDULE (

        repeat_interval  => 'FREQ=MONTHLY;BYMONTHDAY=1',
     
        schedule_name  => '"UPDATE_CURRENT_SALARY_SCHEDULE"');

END;


BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
            job_name => '"APM_COMPANY"."UPDATE_CURRENT_SALARY_JOB"',
            program_name => '"APM_COMPANY"."UPDATE_CURRENT_SALARY"',
            schedule_name => '"APM_COMPANY"."UPDATE_CURRENT_SALARY_SCHEDULE"',
            enabled => FALSE,
            auto_drop => FALSE,
            comments => '',
               
            job_style => 'REGULAR');

         
     
 
    DBMS_SCHEDULER.SET_ATTRIBUTE( 
             name => '"APM_COMPANY"."UPDATE_CURRENT_SALARY_JOB"', 
             attribute => 'store_output', value => TRUE);
    DBMS_SCHEDULER.SET_ATTRIBUTE( 
             name => '"APM_COMPANY"."UPDATE_CURRENT_SALARY_JOB"', 
             attribute => 'logging_level', value => DBMS_SCHEDULER.LOGGING_OFF);
      
   
  
    
    DBMS_SCHEDULER.enable(
             name => '"APM_COMPANY"."UPDATE_CURRENT_SALARY_JOB"');
END;


BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
            job_name => '"APM_COMPANY"."ANNUAL_SALARY_UPDATE"',
            job_type => 'PLSQL_BLOCK',
            job_action => 'BEGIN
DBMS_SCHEDULER.set_attribute( name => ''"APM_COMPANY"."UPDATE_SALARY"'', attribute => ''job_action'', value => ''begin
EXECUTE IMMEDIATE q''''{

UPDATE apm_employees
SET salary = salary + 200
WHERE hire_date = add_months (trunc(sysdate), -240)

}'''';
end;'');

END;',
            number_of_arguments => 0,
            start_date => TO_TIMESTAMP_TZ('2023-01-01 01:01:01.000000000 EUROPE/BELGRADE','YYYY-MM-DD HH24:MI:SS.FF TZR'),
            repeat_interval => NULL,
            end_date => NULL,
            enabled => FALSE,
            auto_drop => FALSE,
            comments => '');

         
     
 
    DBMS_SCHEDULER.SET_ATTRIBUTE( 
             name => '"APM_COMPANY"."ANNUAL_SALARY_UPDATE"', 
             attribute => 'store_output', value => TRUE);
    DBMS_SCHEDULER.SET_ATTRIBUTE( 
             name => '"APM_COMPANY"."ANNUAL_SALARY_UPDATE"', 
             attribute => 'logging_level', value => DBMS_SCHEDULER.LOGGING_OFF);
      
   
  
    
    DBMS_SCHEDULER.enable(
             name => '"APM_COMPANY"."ANNUAL_SALARY_UPDATE"');
END;

CREATE OR REPLACE TYPE t_salary_queue_payload AS OBJECT (
  event_name  VARCHAR2(30)
);

BEGIN
  DBMS_AQADM.create_queue_table(
    queue_table        => 'salary_queue_tab',
    queue_payload_type => 't_salary_queue_payload',
  MESSAGE_GROUPING => DBMS_AQADM.TRANSACTIONAL, 
    sort_list => 'COMMIT_TIME', 
    compatible => '10.1',
    multiple_consumers => true, 
    comment            => 'Queue Table For Events');


  DBMS_AQADM.create_queue (
    queue_name  => 'salary_queue',
    queue_table => 'salary_queue_tab');

  DBMS_AQADM.start_queue (queue_name => 'salary_queue');
END;


BEGIN
   DBMS_SCHEDULER.create_job (
      job_name        => 'event_based_salary_update_job',
      job_type        => 'PLSQL_BLOCK',
      job_action      => 'BEGIN
                            EXECUTE IMMEDIATE q''{

UPDATE apm_employees
SET salary = salary + 150
WHERE manager_id = 100

}'';
                          END;',
      start_date      => SYSTIMESTAMP,
      event_condition => 'tab.user_data.event_name = ''Wrong_salary_value''',
      queue_spec      => 'salary_queue',
      enabled         => false);
   
    dbms_scheduler.set_attribute('event_based_salary_update_job','parallel_instances',TRUE);   
 
 dbms_scheduler.enable('event_based_salary_update_job');
END;

BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
            job_name => '"APM_COMPANY"."CHECK_MANAGERS_SALARY"',
            job_type => 'PLSQL_BLOCK',
            job_action => 'DECLARE
  CURSOR cur_mgr IS
      SELECT m.fname,
             m.surname,
             m.salary
      FROM apm_employees e
      INNER JOIN apm_employees m ON m.manager_id = e.emp_id
      WHERE m.salary < e.salary;
  l_enqueue_options     DBMS_AQ.enqueue_options_t;
  l_message_properties  DBMS_AQ.message_properties_t;
  l_message_handle      RAW(16);
  l_queue_msg           t_salary_queue_payload;

  v_mgr cur_mgr%ROWTYPE;
BEGIN
  OPEN cur_mgr;
  FETCH cur_mgr INTO v_mgr;
  IF v_mgr.salary is not null
  then
BEGIN
  l_queue_msg := t_salary_queue_payload(''Wrong_salary_value'');

  DBMS_AQ.enqueue(queue_name          => ''salary_queue'',
                  enqueue_options     => l_enqueue_options,
                  message_properties  => l_message_properties,
                  payload             => l_queue_msg,
                  msgid               => l_message_handle);
  COMMIT;
END;
  end if;
  CLOSE cur_mgr;
END;',
            number_of_arguments => 0,
            start_date => NULL,
            repeat_interval => 'FREQ=MONTHLY;BYMONTHDAY=1',
            end_date => NULL,
            enabled => FALSE,
            auto_drop => FALSE,
            comments => '');

         
     
 
    DBMS_SCHEDULER.SET_ATTRIBUTE( 
             name => '"APM_COMPANY"."CHECK_MANAGERS_SALARY"', 
             attribute => 'store_output', value => TRUE);
    DBMS_SCHEDULER.SET_ATTRIBUTE( 
             name => '"APM_COMPANY"."CHECK_MANAGERS_SALARY"', 
             attribute => 'logging_level', value => DBMS_SCHEDULER.LOGGING_OFF);
      
   
  
    
    DBMS_SCHEDULER.enable(
             name => '"APM_COMPANY"."CHECK_MANAGERS_SALARY"');
END;


declare a number(3) :=100;
begin
select dayofmonth into a from apm_task_manager where job_name='ANNUAL_SALARY_UPDATE';
DBMS_SCHEDULER.set_attribute(
        name      => 'ANNUAL_SALARY_UPDATE',
        attribute => 'REPEAT_INTERVAL',
        value     => 'FREQ=MONTHLY;INTERVAL=12;BYMONTHDAY='||a||'');
select dayofmonth into a from apm_task_manager where job_name='CHECK_MANAGERS_SALARY';
DBMS_SCHEDULER.set_attribute(
        name      => 'CHECK_MANAGERS_SALARY',
        attribute => 'REPEAT_INTERVAL',
        value     => 'FREQ=MONTHLY;BYMONTHDAY='||a||'');
for a in (select job_name,set_enabled from apm_task_manager)
loop
if (a.set_enabled=0) then
dbms_scheduler.disable(name => a.job_name);
else 
DBMS_SCHEDULER.enable(name => a.job_name);
end if;
dbms_output.put_line(a.job_name);
end loop;
UPDATE apm_task_manager
SET    last_start_date  = (SELECT trunc (last_start_date)
                FROM   sys.all_scheduler_jobs
                WHERE  apm_task_manager.job_name = sys.all_scheduler_jobs.job_name);
UPDATE apm_task_manager
SET    next_start_date  = (SELECT trunc (next_run_date)
                FROM   sys.all_scheduler_jobs
                WHERE  apm_task_manager.job_name = sys.all_scheduler_jobs.job_name);
UPDATE apm_task_manager
SET    actual_enabled  = (SELECT sys.all_scheduler_jobs.enabled
                FROM   sys.all_scheduler_jobs
                WHERE  apm_task_manager.job_name = sys.all_scheduler_jobs.job_name);
UPDATE apm_task_manager
SET    last_state  = (SELECT dba_scheduler_job_run_details.status
                FROM   dba_scheduler_job_run_details
                WHERE  apm_task_manager.job_name = dba_scheduler_job_run_details.job_name
                fetch first 1 row only);
UPDATE apm_task_manager
SET    error  = (SELECT dba_scheduler_job_run_details.error#
                FROM   dba_scheduler_job_run_details
                WHERE  apm_task_manager.job_name = dba_scheduler_job_run_details.job_name
                fetch first 1 row only);
end;

stworzenie joba


BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
            job_name => '"APM_COMPANY"."JOBS_SCHEDULING_MANAGER"',
            job_type => 'PLSQL_BLOCK',
            job_action => declare a number(3) :=100;
begin
select dayofmonth into a from apm_task_manager where job_name='ANNUAL_SALARY_UPDATE';
DBMS_SCHEDULER.set_attribute(
        name      => 'ANNUAL_SALARY_UPDATE',
        attribute => 'REPEAT_INTERVAL',
        value     => 'FREQ=MONTHLY;INTERVAL=12;BYMONTHDAY='||a||'');
select dayofmonth into a from apm_task_manager where job_name='CHECK_MANAGERS_SALARY';
DBMS_SCHEDULER.set_attribute(
        name      => 'CHECK_MANAGERS_SALARY',
        attribute => 'REPEAT_INTERVAL',
        value     => 'FREQ=MONTHLY;BYMONTHDAY='||a||'');
for a in (select job_name,set_enabled from apm_task_manager)
loop
if (a.set_enabled=0) then
dbms_scheduler.disable(name => a.job_name);
else 
DBMS_SCHEDULER.enable(name => a.job_name);
end if;
dbms_output.put_line(a.job_name);
end loop;
UPDATE apm_task_manager
SET    last_start_date  = (SELECT trunc (last_start_date)
                FROM   sys.all_scheduler_jobs
                WHERE  apm_task_manager.job_name = sys.all_scheduler_jobs.job_name);
UPDATE apm_task_manager
SET    next_start_date  = (SELECT trunc (next_run_date)
                FROM   sys.all_scheduler_jobs
                WHERE  apm_task_manager.job_name = sys.all_scheduler_jobs.job_name);
UPDATE apm_task_manager
SET    actual_enabled  = (SELECT sys.all_scheduler_jobs.enabled
                FROM   sys.all_scheduler_jobs
                WHERE  apm_task_manager.job_name = sys.all_scheduler_jobs.job_name);
UPDATE apm_task_manager
SET    last_state  = (SELECT dba_scheduler_job_run_details.status
                FROM   dba_scheduler_job_run_details
                WHERE  apm_task_manager.job_name = dba_scheduler_job_run_details.job_name
                fetch first 1 row only);
UPDATE apm_task_manager
SET    error  = (SELECT dba_scheduler_job_run_details.error#
                FROM   dba_scheduler_job_run_details
                WHERE  apm_task_manager.job_name = dba_scheduler_job_run_details.job_name
                fetch first 1 row only);
end;',
            number_of_arguments => 0,
            start_date => NULL,
            repeat_interval => 'FREQ=MINUTELY',
            end_date => NULL,
            enabled => FALSE,
            auto_drop => FALSE,
            comments => '');

         
     
 
    DBMS_SCHEDULER.SET_ATTRIBUTE( 
             name => '"APM_COMPANY"."JOBS_SCHEDULING_MANAGER"', 
             attribute => 'store_output', value => TRUE);
    DBMS_SCHEDULER.SET_ATTRIBUTE( 
             name => '"APM_COMPANY"."JOBS_SCHEDULING_MANAGER"', 
             attribute => 'logging_level', value => DBMS_SCHEDULER.LOGGING_OFF);
      
   
  
    
    DBMS_SCHEDULER.enable(
             name => '"APM_COMPANY"."JOBS_SCHEDULING_MANAGER"');
END;
