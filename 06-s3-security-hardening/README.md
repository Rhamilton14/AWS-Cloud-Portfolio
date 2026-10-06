# S3 Security Hardening: "Secure the Bucket"

### Objective
Take an S3 bucket that is exposing sensitive data and secure it with layered controls: defense in depth.

### What I did
I confirmed that anyone with a link could read a password file, then turned on Block Public Access. I replaced an open bucket policy with a least-privilege policy that only allows one Lambda role, and showed that the Lambda could still read the data while my own user was denied. Finally, I required HTTPS for all requests and switched default encryption to SSE-KMS.

### Services I learned
- **Amazon S3**: Block Public Access, bucket policies and default encryption
- **AWS IAM**: least-privilege roles and policies
- **AWS KMS**: encrypting data at rest with KMS keys
- **AWS Lambda**: an app accessing S3 through its IAM role
- **CloudShell**: testing access from the command line

## Before and after

| Control | Before | After |
|---|---|---|
| Public access | Anyone with the URL could read `user-passwords.json` | Block Public Access on, URL returns **403** |
| Bucket policy | `"Principal": "*"` could get and list | Only the app's Lambda role can read |
| In transit | HTTP allowed | `aws:SecureTransport` deny, HTTPS only |
| At rest | SSE-S3 default | **SSE-KMS** with a bucket key |

## Steps
1. **Block public access.** Confirmed the object URL was readable from any browser, enabled *Block all public access*, and confirmed a 403.
2. **Least-privilege bucket policy.** Showed that any authenticated user could still read it from CloudShell (`aws s3 cp s3://<bucket>/sensitive-data/user-passwords.json -`). Replaced the [original policy](policies/01-original-insecure-policy.json) with a [deny-all-except-the-Lambda-role policy](policies/02-lambda-role-only-policy.json). CloudShell now gets *Access Denied*.
3. **IAM role access.** Invoked a Lambda whose role only has `s3:GetObject` and `s3:ListBucket` on this one bucket. It can still list and read the files, while my user can't.
4. **Enforce HTTPS.** Added a [`DenyInsecureTransport` statement](policies/03-https-only-policy.json).
5. **Encryption at rest.** Switched default encryption to SSE-KMS with an S3 bucket key to cut KMS request costs.

## Screenshots
<!-- ![403 after blocking public access](screenshots/403.png) -->
<!-- ![CloudShell access denied](screenshots/access-denied.png) -->
<!-- ![Lambda reads successfully](screenshots/lambda-success.png) -->

## What I learned
- **Defense in depth:** the bucket policy controls *who* can reach the bucket, the IAM role controls *what* the function can do, and both must allow access.
- An explicit Deny with a condition is how you carve out a single allowed principal.
- Other best practices: versioning (can be suspended but never fully disabled), Object Lock, lifecycle rules, VPC endpoints, and CloudTrail/CloudWatch monitoring.
