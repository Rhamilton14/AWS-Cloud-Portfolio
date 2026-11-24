# Cost Estimate

Approximate monthly cost in **us-east-1** for the baseline of 2 instances running 24/7 with light traffic. Prices change, so confirm current rates with the [AWS Pricing Calculator](https://calculator.aws/).

| Component | Calculation | Approx. Monthly |
|---|---|---|
| Application Load Balancer | about $0.0225/hr × 730 hrs, plus a small LCU charge | ~$17–20 |
| EC2 (2 × t3.micro) | about $0.0104/hr × 730 hrs × 2 | ~$15 |
| EBS (2 × 8 GB gp3) | about $0.08/GB-month × 16 GB | ~$1.30 |
| DynamoDB on-demand | Pay per request. Light traffic costs cents | <$1 |
| VPC gateway endpoints | Free | $0 |
| **Total** | | **≈ $35/month** |

*The AWS Free Tier can cover much of the EC2 and ALB cost for new accounts.*

## The Biggest Cost Decision: Avoiding NAT Gateways

Private servers usually reach AWS services through a **NAT gateway**, which costs about **$0.045/hr (~$33/month) per AZ** plus data processing charges. A highly available setup needs one per AZ, which adds **about $66 a month or more**.

This design uses **VPC gateway endpoints** for DynamoDB and S3 instead. They're **free**, and traffic never leaves the AWS network.

| Option | Monthly Cost for 2 AZs |
|---|---|
| NAT gateways | ~$66+ |
| Gateway endpoints (this design) | **$0** |

That nearly **halves the total bill**.

**Trade-off:** gateway endpoints only cover DynamoDB and S3. If the servers needed general internet access (for example to call a third-party API), you would need a NAT gateway.

## Using the AWS Pricing Calculator
1. Go to [calculator.aws](https://calculator.aws/) and click **Create estimate**.
2. Add **Elastic Load Balancing**, **Amazon EC2** and **Amazon DynamoDB**.
3. Enter the values from the table above.
4. Compare it with a version that includes **VPC → NAT Gateway** to see the savings.
