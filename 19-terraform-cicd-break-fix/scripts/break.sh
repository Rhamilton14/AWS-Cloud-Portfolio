#!/usr/bin/env bash
# The intentional break: simulate someone "cleaning up" a security group in the
# console. Deletes the rule that lets the load balancer reach the app servers.
# Run from 19-terraform-cicd-break-fix/ after `terraform apply`.
set -euo pipefail
cd "$(dirname "$0")/../terraform"

app_sg=$(terraform output -raw app_security_group_id)
alb_sg=$(terraform output -raw alb_security_group_id)

rule_id=$(aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$app_sg" \
  --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId=='$alb_sg'].SecurityGroupRuleId" \
  --output text)

if [ -z "$rule_id" ] || [ "$rule_id" = "None" ]; then
  echo "No ALB -> app rule found. Already broken?"; exit 1
fi

echo "Breaking: deleting rule $rule_id (ALB -> app on the app port) from $app_sg"
aws ec2 revoke-security-group-ingress --group-id "$app_sg" --security-group-rule-ids "$rule_id"
echo "Broken at $(date -u +%H:%M:%S) UTC. Start your timer."
