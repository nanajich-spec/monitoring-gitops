# Airflow Metrics Dashboard

## Overview

The Airflow DAG Metrics dashboard provides comprehensive visibility into Airflow DAG execution, task performance, resource usage, and operational status.

## Dashboard Access

- **URL**: http://172.28.229.33:30030/d/airflow-dag-metrics/airflow-dag-metrics-and-performance
- **UID**: `airflow-dag-metrics`
- **Refresh**: 30 seconds
- **Tags**: airflow, dags, metrics

## Metrics Source

- **Endpoint**: `airflow-statsd.airflow.svc.cluster.local:9102/metrics`
- **Exporter**: StatsD to Prometheus exporter (built into Airflow Helm chart)
- **ServiceMonitor**: `airflow-metrics` in airflow namespace
- **Scrape Interval**: 30 seconds

## Dashboard Panels

### Statistics Row (Top)

1. **Total DAGs** - Current number of DAGs in dagbag
   - Metric: `airflow_dagbag_size`
   - Current Value: 10 DAGs

2. **Successful Runs (1h)** - Number of successful DAG runs in last hour
   - Metric: `increase(airflow_dagrun_duration_success_count[1h])`

3. **Failed Tasks (1h)** - Number of failed tasks in last hour
   - Metric: `sum(increase(airflow_ti_finish{state="failed"}[1h]))`
   - Color: Red when > 0

4. **Successful Tasks (1h)** - Number of successful tasks in last hour
   - Metric: `sum(increase(airflow_ti_finish{state="success"}[1h]))`
   - Color: Green

5. **Open Executor Slots** - Available slots in executor
   - Metric: `airflow_executor_open_slots`
   - Color: Yellow when < 2, Red when 0

6. **Queued Tasks** - Currently queued tasks waiting for execution
   - Metric: `airflow_executor_queued_tasks`
   - Color: Yellow when > 5, Red when > 10

7. **Running Tasks** - Currently executing tasks
   - Metric: `airflow_executor_running_tasks`

8. **Import Errors** - Number of DAG import errors
   - Metric: `airflow_dag_processing_import_errors`
   - Color: Yellow when > 0

### Timeseries Graphs

9. **Task Success/Failure Rate** - Task completion rate over time
   - Success: `sum by (dag_id, task_id) (increase(airflow_ti_finish{state="success"}[5m]))`
   - Failure: `sum by (dag_id, task_id) (increase(airflow_ti_finish{state="failed"}[5m]))`
   - Shows breakdown by DAG and task

10. **Task Duration** - Average task execution time
    - Metric: `avg(airflow_dagrun_duration_success_sum / airflow_dagrun_duration_success_count)`
    - Unit: seconds

11. **CPU Usage by Pod** - CPU utilization per Airflow pod
    - Metric: `rate(container_cpu_usage_seconds_total{namespace="airflow"}[5m])`
    - Unit: percent (0-1)

12. **Memory Usage by Pod** - Memory consumption per Airflow pod
    - Metric: `container_memory_working_set_bytes{namespace="airflow"}`
    - Unit: bytes (auto-formatted)

### Tables

13. **Pod Status** - Current status of all Airflow pods
    - Columns: Pod, Status, Node, Age
    - Metrics: `kube_pod_info`, `kube_pod_status_phase`

14. **Restart Count** - Pods sorted by restart count
    - Columns: Pod, Restarts
    - Metric: `kube_pod_container_status_restarts_total{namespace="airflow"}`
    - Sorted descending by restart count

## Available Airflow Metrics

### DAG Metrics
- `airflow_dagbag_size` - Total number of DAGs
- `airflow_dag_processing_import_errors` - DAG import errors
- `airflow_dag_processing_last_duration` - Last processing duration
- `airflow_dag_processing_processes` - Number of DAG processing processes
- `airflow_dagrun_duration_success_*` - DAG run duration (success)
- `airflow_dagrun_duration_failed_*` - DAG run duration (failed)
- `airflow_dagrun_schedule_delay_*` - DAG run schedule delay

### Task Metrics
- `airflow_ti_start` - Task instance start events
- `airflow_ti_finish{state="success|failed|..."}` - Task instance completion by state
- `airflow_ti_failures` - Task failures
- `airflow_ti_successes` - Task successes
- `airflow_task_duration_*` - Task execution duration
- `airflow_task_queued_duration_*` - Time task spent in queue
- `airflow_task_cpu_usage_*` - CPU usage per task (by DAG and task)
- `airflow_task_mem_usage_*` - Memory usage per task (by DAG and task)

### Executor Metrics
- `airflow_executor_open_slots` - Available executor slots
- `airflow_executor_queued_tasks` - Tasks waiting in queue
- `airflow_executor_running_tasks` - Currently running tasks

### Scheduler Metrics
- `airflow_scheduler_heartbeat` - Scheduler heartbeat
- `airflow_scheduler_loop_duration_*` - Scheduler loop duration
- `airflow_scheduler_tasks_executable` - Executable tasks
- `airflow_scheduler_tasks_starving` - Tasks waiting for resources
- `airflow_scheduler_tasks_running` - Currently running tasks
- `airflow_scheduler_critical_section_duration_*` - Critical section duration

### Pool Metrics
- `airflow_pool_open_slots_*` - Open pool slots by pool name
- `airflow_pool_running_slots_*` - Running pool slots by pool name
- `airflow_pool_queued_slots_*` - Queued pool slots by pool name

### Operator Metrics
- `airflow_operator_successes_*` - Success count by operator type
- `airflow_operator_failures_*` - Failure count by operator type
- `airflow_task_instance_created_*` - Task instance creation events

## Monitoring Best Practices

### Alert Thresholds

1. **Failed Tasks** - Alert when failed tasks > 0 in last 5 minutes
2. **Queued Tasks** - Warning when > 5, Critical when > 10
3. **Open Slots** - Warning when < 2, Critical when 0
4. **Import Errors** - Warning when > 0
5. **Memory Usage** - Warning when > 80% of limits

### Key Metrics to Watch

- **DAG Success Rate**: Should stay > 95%
- **Task Duration**: Watch for sudden increases (performance degradation)
- **Executor Slots**: Should have available capacity
- **Pod Restarts**: Frequent restarts indicate instability

## Troubleshooting

### No Data in Dashboard

1. Check ServiceMonitor exists:
   ```bash
   microk8s kubectl get servicemonitor -n airflow airflow-metrics
   ```

2. Verify Prometheus scraping:
   ```bash
   curl -s 'http://172.28.229.33:30090/api/v1/query?query=airflow_dagbag_size'
   ```

3. Check airflow-statsd pod is running:
   ```bash
   microk8s kubectl get pods -n airflow -l component=statsd
   ```

4. Test metrics endpoint directly:
   ```bash
   microk8s kubectl exec -n airflow <statsd-pod> -- wget -qO- http://localhost:9102/metrics | grep airflow
   ```

### Metrics Show Zero Values

- Wait for DAGs to run (metrics populate after execution)
- Check DAG scheduling is enabled
- Verify tasks are actually executing
- Review Airflow logs for errors

## Files

- **ServiceMonitor**: `configs/airflow-metrics-scrape.yaml`
- **Dashboard JSON**: `dashboards/airflow-dag-metrics.json`
- **ConfigMap**: `configs/grafana-airflow-dashboard.yaml`

## Updates

Last Updated: 2024-12-20
- Added comprehensive 14-panel dashboard
- Integrated 170+ Airflow StatsD metrics
- Included task-level CPU/memory metrics
- Added executor and scheduler visibility
