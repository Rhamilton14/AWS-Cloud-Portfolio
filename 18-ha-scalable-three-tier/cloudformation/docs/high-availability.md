# Making the Architecture Highly Available and Scalable

**High availability** means the app stays up when something fails.
**Scalability** means the app handles more traffic by adding capacity.

## Before and After

| | Single-Server Setup | This Design |
|---|---|---|
| Servers | 1 EC2 instance | 2 to 4 instances in an Auto Scaling group |
| Data centers | 1 Availability Zone | 2 Availability Zones |
| Server fails | Site goes down | Traffic shifts to healthy servers and a replacement launches |
| AZ outage | Site goes down | The other AZ keeps serving |
| Traffic spike | Server slows down or crashes | New servers launch automatically |
| Database | Tied to one server | DynamoDB, replicated across 3 AZs by AWS |

## The Building Blocks

### 1. Multiple Availability Zones
Each AZ is a separate data center with its own power and networking. The public and private subnets are duplicated in two AZs, so a whole-AZ failure takes down only half the capacity.

### 2. Auto Scaling Group
- **Minimum 2** instances, one per AZ, so there's never a single point of failure.
- **Maximum 4** instances, so costs stay capped.
- **Self-healing:** if an instance fails its health check, it's replaced automatically.

### 3. ELB Health Checks
The ALB checks `/health` on every server every 15 seconds. After 2 failed checks, it stops sending traffic to that server. Because the Auto Scaling group uses `HealthCheckType: ELB`, it then replaces the server.

### 4. Target Tracking Scaling
The group aims to keep **average CPU at 50%**. Above that it adds servers, and when traffic drops it removes them. It works like a thermostat.

### 5. Stateless App Servers
The servers don't store anything locally. All data lives in DynamoDB. That means any server can handle any request, and servers can be added or removed safely.

## Proving It Works

| Test | How | Expected Result |
|---|---|---|
| Load balancing | Refresh the app URL several times | `served_by` and `availability_zone` change |
| Self-healing | Terminate one EC2 instance | The site stays up and a new instance appears in a few minutes |
| Scale out | Generate load (for example `ab -n 100000 -c 50 <url>/`) | The instance count rises toward 4 |
| Shared data | Refresh on different servers | `total_visits` keeps counting up, whichever server answers |
