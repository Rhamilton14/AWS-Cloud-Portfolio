# Terraform, CI/CD and a Break/Fix: One App, Built, Broken and Fixed

> **Status: code complete, live run pending.** Everything below the "Results" markers gets filled in from the real deploy. Follow [RUNBOOK.md](RUNBOOK.md) and replace each `TODO` with what actually happened.

### Objective
Take the three-tier pattern from projects [17](../17-three-tier-architecture/) and [18](../18-ha-scalable-three-tier/), which were deployed for me in a lab account, and build it myself from code. Put an app in a VPC behind a load balancer, provision all of it with **Terraform**, deploy it through a **GitHub Actions** pipeline, monitor it with **CloudWatch**, then break it on purpose, troubleshoot it, and write down exactly what happened.

### What I built
A small Python web app runs on EC2 instances in **private subnets** across two Availability Zones, managed by an **Auto Scaling group** and fronted by an **internet-facing Application Load Balancer**. Every resource is defined in Terraform, with state in a versioned, encrypted S3 bucket. A GitHub Actions pipeline checks every pull request, shows the Terraform plan, and on merge to `main` waits for my approval, applies, rolls the new version out one server at a time and smoke-tests it. CloudWatch alarms and a dashboard watch the app from the load balancer's side. GitHub authenticates to AWS with **OIDC**, so there are no AWS access keys anywhere.

### Services and tools
- **Terraform**: VPC, subnets, security groups, ALB, launch template, ASG, alarms and dashboard as code; remote state in S3 with native locking
- **GitHub Actions**: validate → plan → manual approval → apply → wait for rollout → smoke test, plus a nightly drift check
- **Amazon VPC**: public subnets for the ALB only, private subnets for the servers, no NAT gateway
- **Elastic Load Balancing (ALB)**: `/health` health checks, target group, HTTP listener
- **Amazon EC2 + Auto Scaling**: launch template with IMDSv2, min 2 across AZs, CPU target tracking, rolling instance refresh with auto-rollback
- **Amazon CloudWatch + SNS**: four alarms, a dashboard, email notifications
- **AWS IAM**: GitHub OIDC provider, a read-only plan role and a scoped apply role

## Architecture
```
GitHub ──PR──► validate + plan (read-only role)
       ──merge──► approval ──► apply + rollout + smoke test (apply role)      both via OIDC, no keys
                                     │
                                     ▼
User ──HTTP:80──► ALB (public subnets, us-east-1a + 1b)
                    │  health check GET /health every 15s
                    ▼
              App ASG  min 2 · max 4  (private subnets, us-east-1a + 1b)
              Python app on :8080, no public IPs, no internet route, no IAM role
                    │
                    ▼
              CloudWatch alarms ──► SNS ──► email
              Dashboard: healthy hosts, 5xx, latency, CPU, server count

Security groups:
  ALB SG : 80 in from 0.0.0.0/0   ·  out only to App SG on 8080
  App SG : 8080 in only from ALB SG  ·  no outbound rules
```

| File | What it defines |
|---|---|
| [`terraform/network.tf`](terraform/network.tf) | VPC, 2 public + 2 private subnets, internet gateway, route tables |
| [`terraform/security.tf`](terraform/security.tf) | ALB and app security groups, one resource per rule |
| [`terraform/alb.tf`](terraform/alb.tf) | Load balancer, target group, health check, listener |
| [`terraform/app.tf`](terraform/app.tf) | Launch template, Auto Scaling group, rolling refresh, CPU scaling policy |
| [`terraform/monitoring.tf`](terraform/monitoring.tf) | SNS topic, 4 alarms, dashboard |
| [`bootstrap/main.tf`](bootstrap/main.tf) | State bucket, GitHub OIDC provider, plan and apply roles (run once by hand) |
| [`app/app.py`](app/app.py) | The app: `/` shows version, instance and AZ; `/health` returns 200 |
| [`../.github/workflows/project-19-terraform.yml`](../.github/workflows/project-19-terraform.yml) | The CI/CD pipeline |
| [`../.github/workflows/project-19-drift.yml`](../.github/workflows/project-19-drift.yml) | Nightly drift check |
| [`scripts/`](scripts/) | `break.sh`, `watch.sh`, `diagnose.sh` for the break/fix exercise |

## Why I made these choices
- **No NAT gateway.** The app uses only the Python standard library, so the servers never need the internet. Dropping the NAT saves about $32 a month and removes an outbound path an attacker could use. The trade-off: no `dnf install` and no SSM Session Manager without adding VPC endpoints.
- **No IAM role on the servers.** The app doesn't call any AWS API, so the instances get no credentials at all. That's least privilege taken to zero.
- **The app ships in the launch template.** Changing `app.py` or `app_version` makes a new launch template version, and the ASG's instance refresh replaces servers one at a time, keeping at least 50% healthy. If the new version never passes health checks, auto-rollback puts the old one back. That's a rolling deploy with no extra tooling.
- **ELB health checks on the ASG.** The ASG replaces servers the load balancer says are unhealthy, not just ones EC2 says are stopped. (This turned out to matter in the break/fix.)
- **One Terraform resource per security group rule.** If someone deletes a rule in the console, `terraform plan` shows exactly that rule missing. That's how drift gets caught.
- **Two pipeline roles.** Pull requests get a read-only role and can only plan. Applying needs the `production` GitHub environment, which requires my approval, and the apply role is limited to EC2, ELB, Auto Scaling, CloudWatch and SNS in one region.
- **Alarms from the load balancer's view.** `HealthyHostCount`, `UnHealthyHostCount`, ELB 5xx and p90 latency measure what users experience, and they're free basic metrics.

## Steps
1. **Bootstrap once by hand:** `terraform apply` in `bootstrap/` creates the state bucket, the OIDC provider and the two roles. I put their outputs in repo variables `AWS_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN` and `AWS_APPLY_ROLE_ARN`, and created a `production` environment with myself as required reviewer.
2. **First deploy through the pipeline:** a pull request ran fmt, validate, tflint and a plan of `TODO` resources. Merging it paused for approval, then applied, waited for the instances and passed the smoke test.
3. **Check it works:** refreshing the ALB URL alternates between two instance IDs in two AZs.
4. **Ship a change:** bumping `app_version` to `v2` in a PR rolled out through the instance refresh with no downtime. `TODO: how long the rollout took`
5. **Break it:** see the incident below.
6. **Tear down:** `terraform destroy` after the screenshots. Estimated cost for a weekend: `TODO` (ALB ≈ $0.55/day plus two t3.micro instances, free-tier eligible).

## The break/fix: "someone cleaned up a security group"
**What I broke.** I ran [`scripts/break.sh`](scripts/break.sh), which deletes the app security group's inbound rule from the ALB, the same as someone removing a rule in the console because it "looked unused." Terraform didn't make the change, so the code still says the rule exists.

**Results** (fill in from the live run with [RUNBOOK.md](RUNBOOK.md)):

| Time (UTC) | What happened |
|---|---|
| `TODO` | Ran `break.sh` |
| `TODO` | `watch.sh` started showing `TODO status code` instead of 200 |
| `TODO` | `tf-webapp-unhealthy-hosts` went into ALARM, email received |
| `TODO` | `tf-webapp-no-healthy-hosts` went into ALARM |
| `TODO` | Auto Scaling started replacing "unhealthy" instances |
| `TODO` | Found the cause |
| `TODO` | Ran `terraform apply`, rule restored |
| `TODO` | Targets healthy, alarms back to OK, 200s again |

**How I troubleshot it** (`TODO: confirm each step against what you saw`):
1. **Alarm first.** The dashboard showed healthy hosts dropping to 0 and ELB 5xx climbing.
2. **Target health tells you why.** `describe-target-health` showed reason `TODO` (expected `Target.Timeout`, "Request timed out"). A timeout, not a 404 or 500, means the ALB can't reach the server at all. That points at the network, not the app.
3. **Not the app.** Instances were running and new ones failed the same way, so it wasn't one bad server.
4. **Network path.** The app security group had no inbound rule from the ALB.
5. **Confirm with Terraform.** `terraform plan` showed `aws_vpc_security_group_ingress_rule.app_from_alb will be created`: AWS had drifted from the code.
6. **Fix.** `terraform apply` put the rule back. I didn't fix it by hand in the console, because that would just create a new difference between AWS and the code.

**Root cause:** a manual change outside Terraform removed the only path from the load balancer to the servers.

## Screenshots
<!-- Save these to screenshots/ during the live run (crop out account IDs and ARNs), then uncomment.
**1. Pull request checks: fmt, validate, tflint and the plan summary**
![PR checks](screenshots/01-pr-checks-and-plan.png)

**2. The apply job waiting for approval in the production environment**
![Approval](screenshots/02-approval-gate.png)

**3. Apply, rollout and smoke test passing**
![Apply](screenshots/03-apply-and-smoke-test.png)

**4. The app in the browser: two instance IDs in two AZs**
![App](screenshots/04-app-two-azs.png)

**5. Resource map: ALB in public subnets, instances in private subnets**
![Resource map](screenshots/05-resource-map.png)

**6. Healthy dashboard**
![Dashboard healthy](screenshots/06-dashboard-healthy.png)

**7. watch.sh: 200s turn into errors after break.sh**
![Outage](screenshots/07-outage-status-codes.png)

**8. Alarms in ALARM and the email notification**
![Alarms](screenshots/08-alarms-firing.png)

**9. Target health reason: Request timed out**
![Target health](screenshots/09-target-health-timeout.png)

**10. Auto Scaling replacing instances that can't pass health checks**
![ASG churn](screenshots/10-asg-replacing-instances.png)

**11. terraform plan showing the missing rule as drift**
![Drift](screenshots/11-terraform-plan-drift.png)

**12. Recovery: dashboard back to 2 healthy hosts, alarms OK**
![Recovered](screenshots/12-recovered.png)
-->

## Troubleshooting and surprises
- `TODO: what surprised you in the live run.` Things to watch for:
- **Self-healing can hide the cause.** With ELB health checks, the ASG terminates servers the ALB can't reach and launches new ones, which fail the same way. Replacing servers can't fix a network rule, so the Activity history fills with launches and terminations.
- **An ALB with zero healthy targets "fails open."** It sends traffic to all targets anyway, so users may see 504 timeouts rather than 503s.
- **Fix it in code, not in the console.** A console fix ends the outage but leaves AWS different from Terraform, which is how the outage started.

## What I'd do differently next time
- **Catch drift before users do.** I added a nightly [drift check](../.github/workflows/project-19-drift.yml) that fails if `terraform plan` finds changes. In a real team I'd also remove console write access in production.
- **HTTPS.** Add an ACM certificate and Route 53 domain, and redirect 80 to 443.
- **Apply the exact plan that was reviewed.** The pipeline re-plans at apply time. Saving the plan as an artifact and applying that file would guarantee no surprises between approval and apply.
- **Logs.** Ship app logs with the CloudWatch agent (needs VPC endpoints or a NAT), and turn on ALB access logs to S3.
- **Modules and environments.** Split the VPC and app into modules and add a staging environment the pipeline deploys to first.
- **Policy checks in CI.** Run Checkov or tfsec on every pull request.

## What I learned
- `TODO: write these in your own words after the live run.`
