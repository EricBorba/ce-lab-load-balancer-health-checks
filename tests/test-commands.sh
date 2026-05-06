#!/bin/bash
# Lab M3.03 – Test Commands
# ALB: web-alb-1083040517.eu-central-1.elb.amazonaws.com
# Target Group ARN: arn:aws:elasticloadbalancing:eu-central-1:871939031886:targetgroup/web-servers-tg/7f070e6f5c387b4b

ALB_DNS="web-alb-1083040517.eu-central-1.elb.amazonaws.com"
TG_ARN="arn:aws:elasticloadbalancing:eu-central-1:871939031886:targetgroup/web-servers-tg/7f070e6f5c387b4b"
INSTANCE_1="i-083e43058e4a65809"
INSTANCE_2="i-068aaa92725b633ec"
INSTANCE_3="i-010122176b085bb76"

# --- Test 1: Basic connectivity ---
echo "=== Test 1: Basic Connectivity ==="
curl -s http://$ALB_DNS | grep -E "Instance|AZ"

# --- Test 2: Load distribution (20 requests) ---
echo ""
echo "=== Test 2: Load Distribution (20 requests) ==="
for i in {1..20}; do
  curl -s http://$ALB_DNS | grep "Instance:" | sed 's/.*Instance: //'
done | sort | uniq -c

# --- Test 3: Health endpoint ---
echo ""
echo "=== Test 3: Health Endpoint ==="
curl -s http://$ALB_DNS/health

# --- Test 4: Check target health (all healthy) ---
echo ""
echo "=== Test 4: Target Health (baseline) ==="
aws elbv2 describe-target-health --target-group-arn $TG_ARN

# --- Test 5: Simulate failure – stop instance 2 ---
echo ""
echo "=== Test 5: Simulating Failure (stopping $INSTANCE_2) ==="
# On the instance: kill the python3 process, or:
# aws ec2 stop-instances --instance-ids $INSTANCE_2
sleep 30
aws elbv2 describe-target-health --target-group-arn $TG_ARN

# --- Test 6: Distribution during failure (only 2 instances should appear) ---
echo ""
echo "=== Test 6: Load Distribution During Failure ==="
for i in {1..10}; do
  curl -s http://$ALB_DNS | grep "Instance:" | sed 's/.*Instance: //'
done | sort | uniq -c

# --- Test 7: Recovery – restart app on instance 2 ---
echo ""
echo "=== Test 7: Recovering Instance ==="
# SSH into instance and run:
# sudo bash -c 'nohup python3 /home/ec2-user/app.py > /home/ec2-user/app.log 2>&1 &'
sleep 30
aws elbv2 describe-target-health --target-group-arn $TG_ARN
