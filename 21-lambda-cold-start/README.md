# Lambda Cold Starts: Measure, Compare and Reduce

> **Status: built, not yet run live.** The code, script and test plan are ready. The results table, findings and screenshots below are marked **TODO** and will be filled in from a real run in my AWS account. No numbers on this page are measured yet.

### Objective
Measure how long a Lambda cold start really takes, separate the part I control (my init code) from the part AWS controls, and test what actually shortens it: more memory, a different runtime, lighter init code, or provisioned concurrency. This follows on from [Project 14: Lambda Power Tuning](../14-lambda-power-tuning/), which tuned memory for warm invokes. This project looks at the first invoke.

### What I did
<!-- TODO after the live run: confirm or adjust these steps -->
In my own AWS account, I created a small Python function and an identical Node.js function. A CloudShell script forced a fresh execution environment before each test, invoked the function once cold and once warm, and pulled `Init Duration`, `Duration` and `Billed Duration` from the `REPORT` log line, along with the round-trip time the client saw. I repeated this at four memory sizes, with light and heavy init code, on both runtimes, and then with provisioned concurrency. Finally, I deleted everything.

### Services I learned
- **AWS Lambda**: the execution environment lifecycle (INIT, INVOKE, SHUTDOWN), versions, aliases and provisioned concurrency
- **Amazon CloudWatch Logs**: the `REPORT` line and Logs Insights queries on `@initDuration`
- **AWS CloudShell + AWS CLI**: scripting repeatable tests
- **AWS IAM**: a scoped policy for the test script

## What is a cold start?
Lambda runs each function in an **execution environment**, a small micro-VM. When a request arrives and no environment is free, Lambda has to build a new one first. That extra work is the cold start:

```
Cold invoke
 ├─ AWS: create micro-VM, download code       ── not in any metric, but the client waits for it
 ├─ INIT: start runtime + run module-level code ── "Init Duration" in the REPORT line
 └─ INVOKE: run the handler                    ── "Duration"

Warm invoke (environment reused)
 └─ INVOKE: run the handler                    ── "Duration" only, no Init Duration
```

Environments are reused for later requests, so a cold start happens on the first request, when traffic scales up past the number of warm environments, after a deploy or configuration change, and after an environment has been idle long enough for Lambda to reclaim it.

**Why it matters for cost too:** since August 2025, AWS bills the INIT phase for on-demand functions on managed runtimes, so slow init code now costs money as well as latency.

## How the test works
1. **Force a cold start.** Changing a function's configuration makes Lambda retire its existing environments. The script sets the memory size and a random `COLD_START_NONCE` environment variable, then waits for the update to finish.
2. **Invoke twice.** The first invoke is cold and the second is warm. Both use `--log-type Tail`, which returns the last 4 KB of the log, including the `REPORT` line.
3. **Record four numbers per invoke:**
   - `init_ms`: **Init Duration** from the `REPORT` line (cold invokes only)
   - `duration_ms`: handler time
   - `billed_ms`: what Lambda charged for
   - `client_ms`: wall-clock time of the `aws lambda invoke` call from CloudShell, which is the **first-invoke latency** a caller actually sees. It includes network and environment setup that no Lambda metric shows.
4. **Repeat** each memory size several times and average, because single cold starts vary.

The function also reports from inside: `cold_start` (a module-level flag that is `true` only on the first invoke in an environment), `module_init_ms` (time spent in my own top-level code) and `AWS_LAMBDA_INITIALIZATION_TYPE` (`on-demand` or `provisioned-concurrency`).

## Files
- [`lambda_function.py`](lambda_function.py): the Python test function. `HEAVY_INIT=true` imports boto3 and creates an S3 client at init; `false` uses only the standard library.
- [`index.mjs`](index.mjs): the same function in Node.js, for the runtime comparison
- [`measure-cold-starts.sh`](measure-cold-starts.sh): the CloudShell script that forces cold starts, invokes, and writes a CSV plus an averages table
- [`logs-insights-query.txt`](logs-insights-query.txt): CloudWatch Logs Insights query for cold start count and average init per memory size
- [`policies/measure-cold-starts-cloudshell.json`](policies/measure-cold-starts-cloudshell.json): least-privilege policy for running the tests, limited to functions named `cold-start-*`

The functions themselves only need the AWS managed policy `AWSLambdaBasicExecutionRole` to write logs.

## Steps
1. **Functions:** create `cold-start-python` (Python 3.13, `lambda_function.py`) and `cold-start-node` (Node.js 22, `index.mjs`), both with a 10-second timeout and default execution roles.
2. **Memory sweep:** in CloudShell, upload the script and run it for each function:
   ```bash
   ./measure-cold-starts.sh cold-start-python 5 128 512 1024 1769
   ./measure-cold-starts.sh cold-start-node   5 128 512 1024 1769
   ```
3. **Init code:** set `HEAVY_INIT=true` on the Python function and run the sweep again, to see what importing boto3 at init adds.
   ```bash
   aws lambda update-function-configuration --function-name cold-start-python \
     --environment 'Variables={HEAVY_INIT=true}'
   ./measure-cold-starts.sh cold-start-python 5 128 512 1024 1769
   ```
4. **Provisioned concurrency:** publish a version, point an alias at it, and keep one environment initialized ahead of time. Then invoke the alias.
   ```bash
   VERSION=$(aws lambda publish-version --function-name cold-start-python --query Version --output text)
   aws lambda create-alias --function-name cold-start-python --name live --function-version "$VERSION"
   aws lambda put-provisioned-concurrency-config --function-name cold-start-python \
     --qualifier live --provisioned-concurrent-executions 1
   # wait until Status is READY
   aws lambda get-provisioned-concurrency-config --function-name cold-start-python --qualifier live
   aws lambda invoke --function-name cold-start-python:live --log-type Tail \
     --query LogResult --output text /dev/null | base64 -d | grep REPORT
   ```
   Expected: no `Init Duration` in the `REPORT` line, and `init_type` is `provisioned-concurrency`, because the INIT phase already ran before the request arrived.
5. **Logs Insights:** run [`logs-insights-query.txt`](logs-insights-query.txt) against `/aws/lambda/cold-start-python` to confirm the cold start counts and averages.
6. **Clean up:** delete the provisioned concurrency config first (it bills per hour while it exists), then both functions, their roles and log groups.

## What changes the cold start
This is what the test is designed to check. The **Expected** column is what AWS documents; the **Measured** column is filled from my run.

| Lever | What it changes | Expected | Measured |
|---|---|---|---|
| **Memory size** | Lambda gives CPU in proportion to memory, and INIT runs on that CPU | Init gets shorter as memory rises, most of all when init code is CPU-heavy. Small for a tiny function. | TODO |
| **Runtime** | Interpreted runtimes (Python, Node.js) start in tens to low hundreds of ms. JVM and .NET runtimes start slower unless SnapStart is used. | Python and Node.js should be close to each other | TODO |
| **Init code** | Imports and clients created at module level run in INIT | `HEAVY_INIT=true` (boto3 + client) should add noticeably to Init Duration | TODO |
| **Provisioned concurrency** | Keeps N environments initialized before requests arrive | No Init Duration on requests served by those environments, but it costs per hour whether used or not | TODO |
| **Package size** | Bigger deployment packages take longer to download and unpack | Not tested here; the test function is a single file | n/a |

**Other options I did not test:** Lambda **SnapStart** (now available for Java, Python 3.12+ and .NET 8+) restores a snapshot of an already initialized environment instead of running INIT, and moving work out of module level and into the handler (lazy loading) trades a faster cold start for a slower first call to that code.

## Result
<!-- TODO: paste the averages table printed by measure-cold-starts.sh for each configuration -->

| Configuration | Memory | Avg Init Duration | Avg cold Duration | Avg warm Duration | Cold client latency | Warm client latency |
|---|---|---|---|---|---|---|
| Python, light init | 128 MB | TODO | TODO | TODO | TODO | TODO |
| Python, light init | 1769 MB | TODO | TODO | TODO | TODO | TODO |
| Python, heavy init (boto3) | 128 MB | TODO | TODO | TODO | TODO | TODO |
| Python, heavy init (boto3) | 1769 MB | TODO | TODO | TODO | TODO | TODO |
| Node.js | 128 MB | TODO | TODO | TODO | TODO | TODO |
| Node.js | 1769 MB | TODO | TODO | TODO | TODO | TODO |
| Python, provisioned concurrency | 128 MB | TODO (expected: none) | TODO | TODO | TODO | TODO |

**Headline finding:** TODO after the live run.

## Screenshots
<!-- TODO: capture these during the live run and save them in screenshots/ -->

**1. The two test functions** — TODO `screenshots/01-functions.png`

**2. A cold invoke's REPORT line showing Init Duration** — TODO `screenshots/02-cold-report-line.png`

**3. The warm invoke right after it, with no Init Duration** — TODO `screenshots/03-warm-report-line.png`

**4. Script output: averages across memory sizes** — TODO `screenshots/04-memory-sweep.png`

**5. Light vs heavy init comparison** — TODO `screenshots/05-heavy-init.png`

**6. Provisioned concurrency READY and an invoke with no Init Duration** — TODO `screenshots/06-provisioned-concurrency.png`

**7. Logs Insights query results** — TODO `screenshots/07-logs-insights.png`

## Well-Architected pillars
- **Performance Efficiency:** measure the latency users actually feel, not just handler time. A function with a 5 ms handler can still make its first caller wait much longer.
- **Cost Optimization:** INIT time is now billed on demand, and provisioned concurrency is billed by the hour. Trimming init code saves money for free; provisioned concurrency is worth paying for only where a slow first request really hurts.
- **Reliability:** cold starts pile up during traffic spikes, exactly when timeouts matter most. Knowing the worst-case init time helps set sensible timeouts for callers.

## What I learned
<!-- TODO: rewrite from the live run -->
- TODO
