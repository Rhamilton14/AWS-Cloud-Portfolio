# Application Migration with AWS: Rehost with MGN, Migrate the Database with DMS, Replatform to ECS Fargate

### Objective
Move a self-hosted WordPress shop ("Buy Me A Unicorn", 1,005 products) off its source servers and into AWS three ways: migrate the MySQL database to RDS with **AWS Database Migration Service**, **rehost** the web server on EC2 with **AWS Application Migration Service (MGN)**, and **replatform** it into containers on **ECS Fargate** with the files on **EFS** and the database credentials in **Parameter Store**. Then tear everything down the same day.

### What I did
I followed the AWS workshop *Application Migration with AWS* (us-west-2, Oregon) from scratch in my own account. A CloudFormation stack built the "on-premises" side: a SourceVPC with a WordPress web server and a MySQL 5.7 database server on Ubuntu, and an empty TargetVPC with public and private subnets.

1. **Database:** created RDS MySQL (single-AZ, `db.t3.micro`), then used a DMS replication instance, a source and a target endpoint, and a **full load + CDC** task to copy the `wordpress-db` schema (28 tables) into it.
2. **Rehost:** installed the MGN replication agent on the source web server, waited for continuous block-level replication to reach Healthy, edited the launch template, ran a **test launch**, then a **cutover launch**. I pointed WordPress at the RDS database, confirmed the shop loaded with all 1,005 products, and **finalized the cutover**.
3. **Replatform:** built an ALB and an IP target group, an ECS cluster on Fargate, a task definition (`wordpress:php7.4-apache`, 0.5 vCPU, 1 GiB) with an **EFS** volume for `wp-content` and four **Parameter Store** values injected as secrets, and a service in the private subnets. The shop came up behind the ALB with a healthy target.
4. **Cleanup:** deleted every billable resource, checked each console for leftovers, and confirmed the bill.

I skipped the optional **waves** path, and the **Elastic Disaster Recovery** and **Optimization** sections, to keep the account inside its budget. Disaster Recovery can be done later by re-running the workshop's "Getting started" template.

### Services I learned
- **AWS Database Migration Service (DMS):** replication instance, source and target endpoints, endpoint connection tests, full load + CDC task, table mappings, data validation
- **Amazon RDS (MySQL):** subnet groups, instance sizing, Extended Support, security group rules for a database
- **AWS Application Migration Service (MGN):** replication agent, staging area, launch template, test vs cutover launches, finalize cutover, archive source server
- **Amazon ECS on Fargate, Amazon EFS, Application Load Balancer:** task definitions, EFS mounts with transit encryption, target group health checks, awsvpc networking
- **AWS Systems Manager:** Session Manager for shell access without SSH, Parameter Store (String and SecureString)
- **Cost control:** a $25 monthly budget, hourly-billing awareness, and a full cleanup pass

## Architecture
```
 Source environment (SourceVPC)                       Target environment (TargetVPC, us-west-2)
 ┌─────────────────────────────┐   DMS full load + CDC   ┌──────────────────────────┐
 │ MySQL 5.7 on Ubuntu         │ ──────────────────────► │ RDS MySQL (db.t3.micro)  │
 │ binlog ON, format ROW       │   (replication instance)│ private subnets          │
 └─────────────────────────────┘                         └───────────▲──────────────┘
 ┌─────────────────────────────┐   MGN agent, block-level            │ MySQL 3306
 │ WordPress web server        │ ──────────────────────► Rehost: EC2 t3.micro
 └─────────────────────────────┘   replication              (test → cutover → finalize)

 Replatform:  Internet ─► ALB (LB-SG, public subnets) ─► ECS Fargate task (ECS-Tasks-SG, private subnets)
                                                         ├─ image wordpress:php7.4-apache
                                                         ├─ /var/www/html/wp-content ─► EFS (EFS-SG, 2 mount targets)
                                                         └─ DB_HOST, DB_NAME, DB_USERNAME, DB_PASSWORD ─► Parameter Store
```

## Result

| Stage | What I checked | Result |
|---|---|---|
| Database migration | DMS task status | **Load completed, replication ongoing**, 100%, 28 tables loaded |
| Source readiness | `log_bin`, `binlog_format` | `ON` and `ROW`, which CDC needs |
| Rehost | MGN lifecycle | Healthy replication → **Test in progress** → **Ready for cutover** → **Cutover complete** |
| Rehost | Shop on the new EC2 server | Loads, **1,005 products** read from RDS |
| Replatform | `unicorn-tg` | **1 healthy target** in a private subnet |
| Replatform | Shop through the ALB | Loads from the Fargate task |
| Cleanup | Every console | No instances, volumes, snapshots, Elastic IPs, load balancers, NAT gateways, RDS, DMS or stacks |
| Cost | Billing home | **$14.23 month-to-date, $14.27 forecast**, covered by credits, under the $25 budget |

**The database, the rehosted server and the containerized copy all served the same shop from the same data, and everything was deleted the same day.**

## Steps
1. **Budget first:** upgraded from the Free plan so the credits apply, then created a **$25 monthly budget** with email alerts.
2. **Source environment:** created the CloudFormation stack `ApplicationMigrationWorkshop` in us-west-2 with my own IP address as the allowed address.
3. **Security groups and RDS:** created `RI-SG` (replication instance) and `DB-SG` (database), an RDS subnet group across two private subnets, and `database-1` (MySQL, single-AZ, `db.t3.micro`, 20 GiB gp3, backups and deletion protection off to keep the lab cheap and easy to remove).
4. **DMS setup:** created a DMS subnet group and a `dms.t3.medium` replication instance in TargetVPC with `RI-SG`.
5. **Prepare the source database:** opened a Session Manager shell on the source DB server, created the replication user, enabled the binary log with `binlog_format=ROW`, and restarted MySQL. Verified `log_bin = ON` and `binlog_format = ROW`.
6. **Endpoints and task:** added the replication instance's public IP to the source DB's security group, created a **source** and a **target** endpoint (SSL mode `none`), ran both connection tests, then created the **full load + CDC** task with a `%` selection rule on `wordpress-db` and data validation. It reached **Load completed, replication ongoing** in a few minutes.
7. **MGN setup:** initialized the service, edited the replication and post-launch templates, installed the replication agent on the source web server (8 GiB and 16 GiB disks) with a temporary access key from the stack, and watched the server reach **Healthy**.
8. **Launch template:** changed the instance type to `t3.micro`, subnet to the TargetVPC public subnet, added a new `MigratedWebServer-SG`, the instance profile and a public IP, then made that version the default.
9. **Test, then cutover:** launched a **test instance**, which showed WordPress's *Error establishing a database connection* as expected (it still pointed at the old database). Marked it ready, launched the **cutover instance**, and updated `wp-config.php` with the RDS host, user and password using `sed`. Added `MigratedWebServer-SG` to `DB-SG`'s inbound rules, and the shop loaded.
10. **Finalize cutover** and archive the source server in MGN.
11. **ECS prerequisites:** created `LB-SG`, `ECS-Tasks-SG` and `EFS-SG`, an **EFS** file system with mount targets in both private subnets, copied `wp-content` onto it from the migrated server over NFS, and created four **Parameter Store** values (`DB_HOST`, `DB_NAME`, `DB_USERNAME` as String and `DB_PASSWORD` as SecureString).
12. **ALB and ECS:** created the IP target group `unicorn-tg` and ALB `unicorn-lb`, the cluster `unicorn-cluster` (Fargate, Container Insights on), the task definition `unicorn-task-def`, and the service `unicorn-svc` (1 task, private subnets, no public IP, 120-second health check grace period).
13. **Verify:** the task went Running, the target went Healthy, and the shop loaded through the ALB.
14. **Cleanup, in dependency order:** ECS cluster → ALB and target group → EFS → parameters → migrated EC2 server → MGN source server (archived) and launch template → snapshots and volumes → DMS task → endpoints → replication instance → DMS subnet group → RDS database → RDS subnet group → security groups → CloudFormation stack. Then a final sweep of every console.

## Screenshots

**1. A $25 monthly budget created before any resources**
![Budget created](screenshots/01-budget-created.png)

**2. The source environment stack finished building**
![Stack create complete](screenshots/02-source-stack-create-complete.png)

**3. `DB-SG` created for the target database**
![DB-SG created](screenshots/03-db-sg-created.png)

**4. RDS subnet group across two availability zones**
![RDS subnet group](screenshots/04-rds-subnet-group-created.png)

**5. The RDS database `database-1` Available (`db.t3.micro`)**
![RDS available](screenshots/05-rds-database-available.png)

**6. The DMS replication instance Available (IP addresses and ARNs hidden)**
![DMS replication instance](screenshots/06-dms-replication-instance-available.png)

**7. Source MySQL: binary logging `ON`, format `ROW`**
![Binlog on](screenshots/07-source-binlog-on-row.png)

**8. Source endpoint connection test: Successful**
![Source endpoint test](screenshots/08-source-endpoint-test-successful.png)

**9. Source and target endpoints Active**
![Endpoints active](screenshots/09-dms-endpoints-active.png)

**10. The `replication-cdc` task: load completed, 28 tables, replication ongoing**
![DMS task](screenshots/10-dms-task-load-complete.png)

**11. MGN: the source server with replication Healthy**
![MGN healthy](screenshots/11-mgn-source-server-healthy.png)

**12. Launch settings changed, server Ready for testing**
![Ready for testing](screenshots/12-mgn-ready-for-testing.png)

**13. Test instance launch in progress**
![Test in progress](screenshots/13-mgn-test-in-progress.png)

**14. The test server before repointing the database: "Error establishing a database connection"**
![Database error](screenshots/14-test-server-db-error.png)

**15. Cutover complete**
![Cutover complete](screenshots/15-mgn-cutover-complete.png)

**16. The migrated shop live on EC2, 1,005 products read from RDS**
![Shop live](screenshots/16-migrated-shop-live.png)

**17. ECS cluster `unicorn-cluster` created**
![ECS cluster](screenshots/17-ecs-cluster-created.png)

**18. Task definition `unicorn-task-def` (ARN hidden)**
![Task definition](screenshots/18-ecs-task-definition.png)

**19. Service `unicorn-svc` Active with the task Running**
![ECS service](screenshots/19-ecs-service-running.png)

**20. Target group `unicorn-tg` with one healthy target**
![Target group healthy](screenshots/20-target-group-healthy.png)

**21. The shop served through the load balancer**
![Shop behind ALB](screenshots/21-shop-behind-alb.png)

**22. Cleanup: the ECS cluster deleted**
![ECS cluster deleted](screenshots/22-cleanup-ecs-cluster-deleted.png)

**23. Cleanup: no CloudFormation stacks**
![No stacks](screenshots/23-cleanup-no-stacks.png)

**24. Cleanup: no EBS volumes**
![No volumes](screenshots/24-cleanup-no-volumes.png)

**25. Cleanup: no Elastic IPs**
![No Elastic IPs](screenshots/25-cleanup-no-elastic-ips.png)

**26. Cleanup: no load balancers**
![No load balancers](screenshots/26-cleanup-no-load-balancers.png)

**27. Cleanup: both NAT gateways deleted**
![NAT gateways deleted](screenshots/27-cleanup-nat-gateways-deleted.png)

**28. Billing after cleanup: $14.23 month-to-date, forecast $14.27**
![Billing](screenshots/28-billing-month-to-date.png)

## Well-Architected pillars
- **Cost Optimization:** a budget before the first resource, smallest instance sizes, backups and deletion protection off for a disposable lab, one task and no public IP on the containers, and a same-day teardown.
- **Security:** security groups reference each other instead of open CIDR ranges, the database and containers sit in private subnets, database credentials live in Parameter Store (SecureString for the password) instead of in the task definition, and EFS uses encryption in transit.
- **Reliability:** DMS validation and CDC keep source and target in step until cutover, MGN's test launch proves the server boots before cutover, and ALB health checks gate traffic to the container.
- **Operational Excellence:** Session Manager instead of SSH keys, Container Insights on the cluster, and a documented cleanup order.

## What I learned
- **Test launch before cutover.** MGN's test instance showed the server booting and the expected database error, without touching production. Cutover is the real move, and finalizing it is what lets MGN discard the replicated data.
- **CDC needs the binary log in ROW format.** DMS can only follow changes if the source has `log_bin` on and `binlog_format=ROW`. I checked both with a query before creating the task.
- **Source servers couldn't register with Session Manager at first.** The role, route table, DNS settings and network ACL were all fine. The old Ubuntu image's SSM agent only worked after I set the instance metadata option to **IMDSv2 optional** and rebooted.
- **Quoting matters in the shell.** A `!` in a database password triggered "event not found" in bash history expansion, and I once ran a `sed` command with the placeholder text instead of the real password. I reset the RDS master password to letters and numbers and verified the login with the `mysql` client before testing the site.
- **Security groups and the console differ from the guide.** The ECS console had changed (the JSON editor opened by default, load balancing had to be switched on), and EFS mount target security groups were greyed out until I deleted and re-added the mount targets with the VPC set back to TargetVPC.
- **RDS and Extended Support.** MySQL 8.0 is past standard support, so RDS required Extended Support to be turned on at creation.
- **Cleanup has an order.** The security groups I created by hand, and the MGN service's own groups, had to go before CloudFormation could delete the VPC. A leftover snapshot from an earlier attempt also blocked "create final snapshot" on RDS.
- **Check every console.** Volumes, snapshots, Elastic IPs, NAT gateways and load balancers can all keep billing after the main resources are gone.

## Interview questions
- **Rehost, replatform, refactor?** Rehost moves the server as it is (MGN here). Replatform changes the runtime without changing the application (WordPress into containers on Fargate, with EFS and Parameter Store). Refactor rewrites the application for cloud-native services.
- **What does DMS do besides copying data?** After the full load, CDC reads the source's binary log and applies ongoing changes, so cutover needs only a short pause. It also validates that rows match.
- **MGN test launch vs cutover launch?** A test launch starts a copy to prove it boots, and replication keeps running. A cutover launch is the real move, and **finalizing** it stops replication and removes the replicated data.
- **Why Parameter Store instead of putting the password in the task definition?** The task definition is visible to anyone who can read it, while a SecureString parameter is encrypted and fetched at start-up by the task execution role.
- **Why EFS for `wp-content`?** Containers are disposable and stateless, so uploads and themes need storage that outlives the task and can be shared by more than one task.
