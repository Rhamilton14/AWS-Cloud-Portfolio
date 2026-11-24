# AWS Well-Architected Review

The [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/) has six pillars. Here is how this architecture addresses each one, and the trade-offs involved.

## 1. Reliability 🛡️
- **Multi-AZ:** servers and load balancer nodes run in two Availability Zones.
- **Self-healing:** the Auto Scaling group replaces unhealthy instances automatically.
- **Managed database:** DynamoDB replicates data across three AZs, and point-in-time recovery is turned on.
- **Trade-off:** the design runs in a single AWS Region. Surviving a full region outage would need a multi-region setup (for example DynamoDB Global Tables and Route 53 failover).

## 2. Security 🔒
- **Network isolation:** app servers sit in private subnets with no public IP addresses.
- **Security group chaining:** the app port only accepts traffic from the ALB's security group.
- **Least privilege:** the EC2 role can only read and write one table.
- **IMDSv2 enforced:** protects instance credentials.
- **Next step:** add HTTPS with an ACM certificate, and put AWS WAF in front of the ALB.

## 3. Cost Optimization 💰
- **No NAT gateway:** free VPC gateway endpoints give private access to DynamoDB and S3.
- **Scales in:** when traffic is low, the group shrinks back to 2 small instances.
- **On-demand DynamoDB:** you pay per request, with no idle capacity.
- **Next step:** use Graviton (`t4g`) instances or Savings Plans for steady workloads.

## 4. Performance Efficiency ⚡
- **Horizontal scaling:** target tracking adds servers as load grows.
- **DynamoDB:** response times stay in single-digit milliseconds at any scale.
- **Next step:** add CloudFront to cache content closer to users.

## 5. Operational Excellence 🔧
- **Infrastructure as code:** one CloudFormation template builds the whole stack.
- **Health checks** give clear signals about which component is failing.
- **Next step:** add CloudWatch alarms and dashboards, and deploy through a CI/CD pipeline.

## 6. Sustainability 🌱
- **Right-sized:** small instances that scale with demand instead of sitting idle.
- **Managed services** (ALB, DynamoDB) share AWS's efficient infrastructure.
