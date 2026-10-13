# Runbook: the live run

Everything here needs your own AWS account and admin credentials. Plan on about 3 hours, and **destroy at the end** (step 8). Take each screenshot listed in the README as you go, and crop out account IDs and ARNs.

## 0. Before you start
- Install the **AWS CLI v2** and **Terraform 1.10 or newer**, then `aws configure` (or `aws sso login`) with an admin user. Check with `aws sts get-caller-identity`.
- Set a **$10 budget alert** in AWS Budgets, just in case.
- Cost while running: about $0.55/day for the ALB plus two t3.micro instances (free-tier eligible). No NAT gateway.

## 1. Bootstrap (once, from your laptop)
```bash
cd 19-terraform-cicd-break-fix/bootstrap
terraform init
terraform apply          # type yes
terraform output         # keep these three values
```
In GitHub, under **Settings → Secrets and variables → Actions → Variables**, add:

| Variable | Value |
|---|---|
| `AWS_STATE_BUCKET` | `state_bucket` output |
| `AWS_PLAN_ROLE_ARN` | `plan_role_arn` output |
| `AWS_APPLY_ROLE_ARN` | `apply_role_arn` output |
| `AWS_REGION` | `us-east-1` |
| `ALARM_EMAIL` | where alarm emails go (confirm the SNS email after the first apply) |

These are variables, not secrets: none of them is a credential, and OIDC means there are no keys to store. Then under **Settings → Environments**, create `production` and add yourself as a **required reviewer**.

## 2. First deploy through the pipeline
1. Open a pull request that touches `19-terraform-cicd-break-fix/` (if this project's own PR is still open when the variables are set, that one works; otherwise change the README and open a new one).
2. Watch **Format, validate, lint** and **Plan** pass. Open the run summary to see the plan. 📸 01
3. Merge. The **Apply** job pauses on "Waiting for review". 📸 02 Approve it.
4. Apply creates everything, waits for the servers and runs the smoke test. 📸 03 Write down how many resources it created for README step 2.

## 3. Check it
- Open the `app_url` from the apply log. Refresh a few times: the instance ID and AZ change. 📸 04
- EC2 → Load Balancers → your ALB → **Resource map**. 📸 05
- CloudWatch → Dashboards → `tf-webapp-dashboard`. 📸 06

## 4. Set up your laptop to talk to the same state
```bash
cd 19-terraform-cicd-break-fix/terraform
cp backend.hcl.example backend.hcl            # put in your bucket name
cp terraform.tfvars.example terraform.tfvars  # same email as ALARM_EMAIL, or plan will want to change it
terraform init -backend-config=backend.hcl
terraform plan                                # should say "No changes": your laptop and the pipeline agree
```

## 5. Ship a change (optional but a good story)
In a PR, change `app_version` to `"v2"`, merge and approve. Watch EC2 → Auto Scaling groups → **Instance refresh** replace servers one at a time while `scripts/watch.sh` keeps showing 200. Note how long it took.

## 6. Break it
Open two terminals in `19-terraform-cicd-break-fix/`.

**Terminal 1:** `./scripts/watch.sh` and leave it running. You should see `200` every 5 seconds.

**Terminal 2:** `./scripts/break.sh`. Write down the time it prints.

Now **don't fix it yet.** Spend 10 to 15 minutes observing and write down the time of each of these:
- When `watch.sh` stops showing 200, and which code it shows instead (504? 503? 502?). 📸 07
- When each alarm goes into ALARM, and when the email arrives. 📸 08
- What target health says: EC2 → Target groups → `tf-webapp-tg` → Targets, or `./scripts/diagnose.sh`. 📸 09
- What the Auto Scaling group does: Auto Scaling groups → `tf-webapp-asg` → **Activity**. Does it start terminating and launching instances? 📸 10

## 7. Troubleshoot and fix it
Work through it as if you didn't know the cause, and note what each step told you:
1. Dashboard: which metric moved first?
2. Target health reason: a **timeout** means the ALB can't reach the server; a **404/500** would mean the app answered badly.
3. Are new instances failing too? Then it's not one bad server.
4. Security groups: does the app SG still allow 8080 from the ALB SG?
5. `terraform plan` 📸 11: it should show `aws_vpc_security_group_ingress_rule.app_from_alb will be created`.

Fix it the right way:
```bash
cd terraform && terraform apply
```
Write down when targets turn healthy, when `watch.sh` shows 200 again, and when the alarms return to OK. 📸 12

Total outage = first non-200 to first 200 again. Time to detect = break to first alarm. Time to fix = alarm to apply.

## 8. Tear down
```bash
cd 19-terraform-cicd-break-fix/terraform && terraform destroy
```
Leave the bootstrap stack if you'll redeploy soon (it costs cents). To remove it too, empty the state bucket (all versions) in the S3 console, then `terraform destroy` in `bootstrap/`.

## 9. Write it up
Fill in every `TODO` in [README.md](README.md), uncomment the screenshots, and add the row to the main README if it isn't there yet.

## The 60-second version for an interview
> "I deployed a Python app on EC2 in private subnets across two AZs, behind an Application Load Balancer, all provisioned with Terraform with remote state in S3. GitHub Actions validates and plans every pull request, then applies on merge after a manual approval, using OIDC so there are no AWS keys in GitHub. Deploys roll out one server at a time with automatic rollback. CloudWatch alarms watch healthy hosts, 5xx errors and latency.
>
> Then I broke it on purpose: I deleted the security group rule that lets the load balancer reach the servers, like someone cleaning up a rule in the console. The site went down with [status code] in [N] seconds, and my alarm fired [N] minutes later. Target health said 'request timed out', which told me it was the network, not the app. Auto Scaling actually made it noisier by replacing servers that were never the problem. `terraform plan` showed the missing rule as drift, and `terraform apply` fixed it in [N] minutes. Afterwards I added a nightly drift-detection job so a change like that gets caught before users notice."
