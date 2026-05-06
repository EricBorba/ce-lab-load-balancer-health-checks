# Lab M3.03 – Load Balancer with Health Checks

## Load Balancer Architecture

This lab deploys a highly available web application across two AWS Availability Zones (eu-central-1a and eu-central-1b) in the Europe (Frankfurt) region. Three EC2 instances (t3.micro) run a Python Flask web application behind an Application Load Balancer (ALB).

```
Internet
    │
    ▼
[ALB: web-alb] (internet-facing, IPv4)
arn:aws:elasticloadbalancing:eu-central-1:871939031886:loadbalancer/app/web-alb/2720dcda6d5afa9d
DNS: web-alb-1083040517.eu-central-1.elb.amazonaws.com
    │
    ├── eu-central-1a (subnet-0ca407a4b0bb5a224 | 10.0.1.0/24)
    │       ├── i-083e43058e4a65809  (web-server-1a)
    │       └── i-068aaa92725b633ec  (web-server-1a-2)
    │
    └── eu-central-1b (subnet-0c3b098bdd986a620 | 10.0.2.0/24)
            └── i-010122176b085bb76  (web-server-1b)
```

**Security Groups:**
- ALB SG: `sg-096196bf5b5532a62` — allows inbound HTTP (port 80) from 0.0.0.0/0
- Web Server SG: `sg-0723cd21f990c0c13` — allows inbound port 80 from ALB SG only

---

## Health Check Configuration

| Parameter | Value | Rationale |
|---|---|---|
| Protocol | HTTP | Application speaks HTTP on port 80 |
| Path | `/health` | Dedicated lightweight endpoint, avoids false positives from main page errors |
| Interval | 10 seconds | Fast enough to detect failures quickly without flooding instances |
| Timeout | 5 seconds | Generous window for instances under load; still within the 10s interval |
| Healthy threshold | 2 consecutive passes | Avoids marking a recovering instance healthy too soon |
| Unhealthy threshold | 2 consecutive failures | Filters transient blips; removes persistently failing targets |

The `/health` endpoint returns a JSON payload (`{"status": "healthy", "instance": "<id>", "az": "<az>"}`) with HTTP 200, giving the ALB a clear signal to route traffic.

---

## Testing Methodology and Results

### Test 1 – Basic Connectivity
Accessed the ALB DNS in the browser and confirmed an HTML response was returned from one of the three instances.

### Test 2 – Load Distribution (20 requests)
```bash
for i in {1..20}; do
  curl -s http://$ALB_DNS | grep "Instance:" | sed 's/.*Instance: //'
done | sort | uniq -c
```

**Results:**
```
6   i-010122176b085bb76   (eu-central-1b)
7   i-068aaa92725b633ec   (eu-central-1a)
7   i-083e43058e4a65809   (eu-central-1a)
```
Traffic was distributed roughly evenly across all three instances, confirming the ALB's least-outstanding-requests algorithm was working.

### Test 3 – Health Check Endpoint
```bash
curl http://$ALB_DNS/health
```
Returns `{"status": "healthy", "instance": "i-083e43058e4a65809", "az": "eu-central-1a"}` with HTTP 200.

### Test 4 – Failover Simulation
Instance `i-068aaa92725b633ec` was stopped to simulate a failure. After ~20 seconds (2 failed health checks × 10s interval), the ALB marked it `unhealthy` with reason `Target.FailedHealthChecks`. Traffic was automatically redistributed to the remaining two healthy instances. The CloudWatch `UnHealthyHostCount` metric in eu-central-1a peaked at 1 during this window.

### Test 5 – Recovery
After restarting the instance and confirming the app was listening on port 80 (`python3 /home/ec2-user/app.py`), the ALB passed 2 consecutive health checks and returned the target to `healthy` status. All three instances resumed receiving traffic.

---

## Failover Scenario Documentation

| Phase | State | Instances Serving Traffic |
|---|---|---|
| Normal operation | All 3 healthy | i-083e43058e4a65809, i-068aaa92725b633ec, i-010122176b085bb76 |
| Instance fails | 1 unhealthy (Target.FailedHealthChecks) | i-083e43058e4a65809, i-010122176b085bb76 |
| Recovery | All 3 healthy again | i-083e43058e4a65809, i-068aaa92725b633ec, i-010122176b085bb76 |

The ALB never sent traffic to the unhealthy instance during the failure window, demonstrating automatic failover with zero manual intervention.

---

## Reflection Questions

**1. How does the load balancer know if an instance is healthy?**
The ALB periodically sends HTTP GET requests to the `/health` path on port 80 of each registered target and expects an HTTP 200 response within the configured timeout. Two consecutive successes mark it healthy; two consecutive failures mark it unhealthy.

**2. What happens when an instance fails a health check?**
The ALB stops routing new requests to that target immediately and redistributes traffic among the remaining healthy instances. The instance stays registered in the target group and is re-evaluated on every health check interval.

**3. Why deploy instances across multiple Availability Zones?**
An AZ is essentially an isolated data center, so placing instances in eu-central-1a and eu-central-1b means a power outage, network issue, or AWS incident affecting one AZ won't take down the entire application. Traffic automatically shifts to the unaffected AZ.

**4. What is the purpose of the /health endpoint?**
It gives the ALB a lightweight, purpose-built signal about application readiness, separate from the main page. A dedicated endpoint can also check internal dependencies (database connectivity, cache availability) and return unhealthy if any critical subsystem is down, even if the web server process itself is still running.

**5. How would you implement sticky sessions? When would you need them?**
You'd enable the `lb_cookie` stickiness attribute on the target group, which makes the ALB set a cookie on the first response and route all subsequent requests from that client to the same instance. Sticky sessions are needed for stateful applications that store session data locally on the instance (e.g., shopping carts, authenticated sessions) rather than in a shared store like ElastiCache or DynamoDB.

---

## Best Practices Learned

- Always use a **dedicated `/health` endpoint** rather than checking `/` — the main page may do expensive database calls that skew health check latency.
- Set the **unhealthy threshold to at least 2** to avoid flapping on transient network blips.
- Keep health check **interval short (10s)** to minimise the window during which an unhealthy instance receives traffic.
- **Multi-AZ deployment is non-negotiable** for production workloads; a single-AZ setup negates most of the value of a load balancer.
- The ALB's **least-outstanding-requests algorithm** (not round-robin) is the default and handles heterogeneous instances more fairly.
- **CloudWatch `UnHealthyHostCount`** is the key metric to alarm on — set a threshold of >= 1 to get immediate notification of any target failure.
