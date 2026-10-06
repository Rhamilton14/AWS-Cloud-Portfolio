# AWS CLI with CloudShell

### Objective
Learn to manage AWS resources from the command line instead of clicking through the Console, and see why the CLI is faster and easier to automate.

### What I did
I used AWS CloudShell to confirm my identity with STS, browse and download files from an S3 bucket, and invoke a Lambda function and read its output. I also tailed and filtered the function's CloudWatch logs and pulled its invocation and error metrics, all with CLI commands.

### Services I learned
- **AWS CLI**: command-line control of every AWS service
- **CloudShell**: a browser terminal that is already signed in with temporary role credentials
- **Amazon S3**: listing, downloading and streaming objects
- **AWS Lambda**: inspecting and invoking functions
- **CloudWatch Logs and Metrics**: troubleshooting and monitoring a function
- **AWS STS**: checking which identity a session is using

## What I did
- Confirmed my CLI identity with STS (CloudShell uses the signed-in IAM role, so no access keys are stored anywhere)
- Listed, browsed and downloaded objects from an S3 bucket, and streamed a file straight to the terminal
- Listed, inspected and invoked a Lambda function, then pretty-printed its JSON output
- Tailed and filtered the function's CloudWatch logs
- Pulled invocation and error counts from CloudWatch Metrics

## Commands I used

```bash
# Who am I?
aws --version
aws sts get-caller-identity

# S3
aws s3 ls
aws s3 ls s3://<bucket>/ --recursive
aws s3 cp s3://<bucket>/welcome.txt ./
aws s3 cp s3://<bucket>/README.md -              # print without downloading
aws s3 cp s3://<bucket>/sample-data/users.json ./ && python3 -m json.tool users.json

# Lambda
aws lambda list-functions --query "Functions[].FunctionName" --output text
aws lambda get-function --function-name <fn> \
  --query 'Configuration.[FunctionName, Runtime, MemorySize, Timeout]' --output table
aws lambda invoke --function-name <fn> output.json && python3 -m json.tool output.json

# CloudWatch Logs
aws logs tail /aws/lambda/<fn> --since 10m
aws logs filter-log-events --log-group-name /aws/lambda/<fn> --filter-pattern "Function invoked"

# CloudWatch Metrics: invocations in the last hour
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Invocations \
  --dimensions Name=FunctionName,Value=<fn> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 --statistics Sum
```

## Screenshots
<!-- Add your own screenshots to ./screenshots and uncomment -->
<!-- ![sts get-caller-identity](screenshots/identity.png) -->
<!-- ![Lambda invoke output](screenshots/lambda-invoke.png) -->

## What I learned
- Anything I can click in the Console I can script with the CLI, which is much faster for repeat work.
- CloudShell authenticates with temporary role credentials, which avoids hard-coded access keys.
- CLI security basics: least-privilege roles, temporary STS credentials over long-lived keys, MFA, and CloudTrail auditing of every call.
