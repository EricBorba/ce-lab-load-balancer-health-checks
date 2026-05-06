# Health Check Failover Test

## Objective
Verify that the ALB detects an unhealthy instance and stops routing traffic to it, then re-adds it after recovery.

## Configuration
- Health check interval: 10 seconds
- Unhealthy threshold: 2 consecutive failures → ~20s to mark unhealthy
- Healthy threshold: 2 consecutive successes → ~20s to mark healthy again

---

## Phase 1 – Baseline (All Healthy)

**Command:**
```bash
aws elbv2 describe-target-health --target-group-arn $TG_ARN
```

**Result:**
| Instance | Health State |
|---|---|
| i-083e43058e4a65809 | healthy |
| i-068aaa92725b633ec | healthy |
| i-010122176b085bb76 | healthy |

Screenshot: `screenshots/target-group-all-healthy.png`

---

## Phase 2 – Simulated Failure

Instance `i-068aaa92725b633ec` was stopped (the application process was killed, causing the `/health` endpoint to become unreachable).

**Wait:** ~20 seconds for 2 failed health checks.

**Result after failure detected:**
| Instance | Health State | Reason |
|---|---|---|
| i-083e43058e4a65809 | healthy | — |
| i-068aaa92725b633ec | **unhealthy** | Target.FailedHealthChecks – Health checks failed |
| i-010122176b085bb76 | healthy | — |

Screenshot: `screenshots/target-group-one-unhealthy.png`

**CloudWatch observation:** `UnHealthyHostCount` metric for eu-central-1a spiked to 1 and remained at 1 throughout the failure window. eu-central-1b (hosting i-010122176b085bb76) stayed at 0.

Screenshot: `screenshots/cloudwatch-unhealthyhostcount.png`

---

## Phase 3 – Traffic During Failure

With only 2 healthy targets, 10 consecutive requests were sent. All responses came from `i-083e43058e4a65809` and `i-010122176b085bb76` only. Instance `i-068aaa92725b633ec` received zero traffic during the unhealthy window, confirming automatic failover.

---

## Phase 4 – Recovery

The application was restarted on `i-068aaa92725b633ec`:
```bash
sudo bash -c 'nohup python3 /home/ec2-user/app.py > /home/ec2-user/app.log 2>&1 &'
```

Port 80 listening was confirmed:
```bash
sudo netstat -tulpn | grep :80
# tcp  0  0  0.0.0.0:80  0.0.0.0:*  LISTEN  2396/python3
```

After ~20 seconds (2 successful health checks), the ALB returned the instance to `healthy` status and all three instances resumed serving traffic.

**Final state:**
| Instance | Health State |
|---|---|
| i-083e43058e4a65809 | healthy |
| i-068aaa92725b633ec | healthy |
| i-010122176b085bb76 | healthy |

---

## Conclusion
The ALB successfully detected the failure within ~20 seconds, automatically removed the unhealthy target from rotation, and re-added it upon recovery — all without manual intervention. Test passed.
