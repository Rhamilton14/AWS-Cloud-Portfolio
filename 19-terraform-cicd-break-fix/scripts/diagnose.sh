#!/usr/bin/env bash
# The troubleshooting commands from the runbook, in order.
set -uo pipefail
cd "$(dirname "$0")/../terraform"

echo "== 1. Alarms currently firing"
aws cloudwatch describe-alarms --alarm-name-prefix tf-webapp --state-value ALARM \
  --query 'MetricAlarms[].[AlarmName,StateUpdatedTimestamp]' --output table

echo "== 2. Target health and the reason the ALB gives"
aws elbv2 describe-target-health --target-group-arn "$(terraform output -raw target_group_arn)" \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' \
  --output table

echo "== 3. Recent Auto Scaling activity (is it replacing servers?)"
aws autoscaling describe-scaling-activities --auto-scaling-group-name "$(terraform output -raw asg_name)" \
  --max-items 6 --query 'Activities[].[StartTime,StatusCode,Description]' --output table

echo "== 4. App security group inbound rules"
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$(terraform output -raw app_security_group_id)" \
  --query 'SecurityGroupRules[?IsEgress==`false`].[SecurityGroupRuleId,FromPort,ReferencedGroupInfo.GroupId,CidrIpv4]' \
  --output table

echo "== 5. Does AWS still match the code?"
terraform plan -input=false -no-color -detailed-exitcode -lock=false | grep -E 'will be|must be|^Plan:|No changes'
