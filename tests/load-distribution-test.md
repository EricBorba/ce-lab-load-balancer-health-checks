# Load Distribution Test

## Objective
Verify that the ALB distributes incoming HTTP requests across all three registered targets.

## Setup
- ALB DNS: `web-alb-1083040517.eu-central-1.elb.amazonaws.com`
- Target Group: `web-servers-tg` (3 instances, all healthy)
- Test volume: 20 consecutive HTTP GET requests

## Command
```bash
for i in {1..20}; do
  curl -s http://$ALB_DNS | grep "Instance:" | sed 's/.*Instance: //'
done | sort | uniq -c
```

## Results

| Requests | Instance ID | Availability Zone |
|---|---|---|
| 7 | i-083e43058e4a65809 | eu-central-1a |
| 7 | i-068aaa92725b633ec | eu-central-1a |
| 6 | i-010122176b085bb76 | eu-central-1b |

**Total requests: 20**

## Analysis
All three instances received traffic. Distribution was 35% / 35% / 30%, which is within expected variance for the ALB's least-outstanding-requests algorithm over 20 requests. Perfect round-robin (33.3% each) is not guaranteed and is not the goal; the algorithm targets even queue depth across targets, not strict alternation. Over hundreds of requests the distribution converges toward equality.

## Conclusion
The load balancer is correctly distributing traffic across all registered targets. Test passed.
