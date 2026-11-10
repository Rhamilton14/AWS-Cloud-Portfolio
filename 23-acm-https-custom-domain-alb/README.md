# HTTPS for a Custom Domain with ACM and an ALB

### Objective
Encrypt traffic in transit for a custom domain: issue a free public certificate with AWS Certificate Manager, prove domain ownership through Route 53, terminate TLS on an Application Load Balancer, redirect every HTTP request to HTTPS, and block anyone who skips the domain and calls the ALB directly.

### What I did
In a course lab account, an internet-facing Application Load Balancer (`customdomain-alb-lambda-l2`, HTTP:80 only) was already deployed in front of a "Hello World" Lambda function (Python 3.11) that reports which protocol the request arrived on, and a Route 53 hosted zone already existed for `bootcamp-student[X].com`. I requested a public **ACM certificate** for the domain, validated it with a **DNS (CNAME) record in Route 53**, added an **HTTPS:443 listener** that uses the certificate, changed the HTTP:80 listener to a **301 redirect to HTTPS**, pointed the apex domain at the ALB with an **alias A record**, and finally added a **Host header rule** so the HTTPS listener only forwards requests for the domain. Everything else gets a fixed **403** from the load balancer.

This is Level 2 of the custom domain lab. [Project 22](../22-route53-custom-domain-alb/) (Level 1) did the alias record and Host header rule over plain HTTP.

*(The lab domain contains my student number, so it's written as `bootcamp-student[X].com` and blacked out in the screenshots.)*

### Services I learned
- **AWS Certificate Manager (ACM)**: public certificates, DNS validation, Pending validation → Issued, managed renewal
- **Amazon Route 53**: CNAME validation records, alias A records at the zone apex
- **Elastic Load Balancing (ALB)**: HTTPS listeners, default SSL certificate, TLS termination, redirect actions (301), Host header rules, fixed-response actions
- **AWS Lambda** as an ALB target, reading the `x-forwarded-proto` header

## Architecture
```
                       DNS lookup
User ───────────────► Route 53  bootcamp-student[X].com
  │                   ├─ A record, Alias ─► ALB
  │                   └─ CNAME _xxxx ─► _xxxx.acm-validations.aws  (proves ownership to ACM)
  │
  ▼
ALB customdomain-alb-lambda-l2
 ├─ HTTP:80  ─► 301 redirect to https://#{host}:443/#{path}?#{query}
 └─ HTTPS:443  (certificate from ACM, TLS ends here)
     ├─ Rule 1: Host header = bootcamp-student[X].com ─► customdomain-lambda-tg-l2 ─► Lambda
     └─ Default: fixed response 403 "Access denied. Please use the custom domain."
```

## Result

| Request | Before (lab start) | After (all tasks) |
|---|---|---|
| `http://[ALB DNS name]` | Hello World, `"protocol": "http"` | 301 → `https://[ALB DNS name]` → **403** |
| `https://[ALB DNS name]` | no listener on 443 | **403** |
| `http://bootcamp-student[X].com` | not set up | **301 → HTTPS**, Hello World, `"protocol": "https"` |
| `https://bootcamp-student[X].com` | not set up | **Hello World, `"protocol": "https"`, padlock, valid certificate** |

**The certificate went from Pending validation to Issued in under 4 minutes, the domain served the Lambda over HTTPS about a minute after the alias record was created, and the redirect and the lockdown both came from the load balancer itself (`Server: awselb/2.0`): `curl -I http://bootcamp-student[X].com` returned a 301 to HTTPS, and `curl -ik https://[ALB DNS name]` returned `HTTP/2 403` with "Access denied. Please use the custom domain." without ever reaching Lambda.**

## Steps
1. **Task 1, test the ALB:** EC2 → Load Balancers → `customdomain-alb-lambda-l2`. Opening `http://[ALB DNS name]` in Safari returned "Hello World from Lambda!" from `CustomDomainALBLambdaHttpsL2-hello-world` (`$LATEST`, environment `dev`) with `"protocol": "http"`: unencrypted in transit.
2. **Task 2, request the certificate:** Certificate Manager → Request a certificate → **Request a public certificate**, domain `bootcamp-student[X].com` (the name is under Route 53 → Registered domains), **DNS validation**. Status: **Pending validation**. The certificate was created as Amazon Issued, RSA 2048 with SHA-256, key source AWS managed, export disabled, and **Renewal eligibility: Ineligible** (it isn't attached to anything yet).
3. **Task 3, validate it:** opened the certificate → **Create records in Route 53**. A CNAME `_[random].bootcamp-student[X].com` → `_[random].acm-validations.aws.` appeared in the hosted zone, and the status changed to **Issued** in under 4 minutes (requested at 14:38, Issued by 14:42). The console also showed a warning that the lab role can't call `acm:SearchCertificates`, a newer ACM API, but listing and using certificates still worked.
4. **Task 4a, HTTPS listener:** Listeners and rules → **Add listener**: HTTPS, 443, forward to `customdomain-lambda-tg-l2`, security policy **ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09** (the console's recommended default), default SSL/TLS certificate **From ACM** (the issued `bootcamp-student[X].com` certificate). Mutual TLS was left off.
5. **Task 4b, redirect HTTP:** changed the HTTP:80 listener's default action to **Redirect to URL**: HTTPS, port 443, keep URI parts, **301 - Permanently moved**. As in Level 1, the default action was changed on the **Edit listener** page (HTTP:80 listener → Edit listener), not by editing a rule.
6. **Check:** the certificate is for `bootcamp-student[X].com`, not for `*.elb.amazonaws.com`, so it can't match the ALB's own address. The lab says to expect a "not secure" page here; I didn't capture one (in Chrome I went straight from the ALB address to the 403 after Task 7).
7. **Task 5, alias record:** Route 53 → hosted zone → Create record: name blank (apex), type **A**, **Alias** on, *Alias to Application and Classic Load Balancer*, US East (N. Virginia), `dualstack.customdomain-alb-lambda-l2-....us-east-1.elb.amazonaws.com`, Simple routing, **Evaluate target health: Yes** (the console default). The alias hosted zone ID was `Z35SXDOTRQ7X7K`, the same as in Level 1, because it identifies ALBs in us-east-1, not one particular ALB.
8. **Task 6, test the domain:** `https://bootcamp-student[X].com` in Chrome returned the Hello World JSON with `"protocol": "https"` and no certificate warning, about 80 seconds after the alias record was created, and `http://bootcamp-student[X].com` redirected to HTTPS.
9. **Task 7 (bonus), block direct ALB access:** on the **HTTPS:443** listener, **Add rule**: condition **Host header** = `bootcamp-student[X].com`, forward to `customdomain-lambda-tg-l2`, priority **1**. Then changed the default action to **Return fixed response**: 403, `text/plain`, "Access denied. Please use the custom domain."
10. **Final test:** the domain still works over HTTPS. The ALB DNS name returns 403 over HTTPS, and over HTTP it is first redirected to HTTPS and then gets the same 403.

## Screenshots

**1. Task 1: the ALB DNS name returns Hello World with `"protocol": "http"`**
![ALB over HTTP](screenshots/01-alb-dns-http.png)

**2. The certificate in Pending validation, with the CNAME name and value ACM wants**
![Pending validation](screenshots/02-cert-pending-validation.png)

**3. Task 3: Create records in Route 53**
![Create records](screenshots/03-create-records-route53.png)

**4. The hosted zone: the new `_xxxx` CNAME pointing to `acm-validations.aws`**
![CNAME record](screenshots/04-hosted-zone-cname.png)

**5. The certificate status: Issued**
![Issued](screenshots/05-cert-issued.png)

**6. Task 4: the HTTPS:443 listener with the ACM certificate**
![HTTPS listener](screenshots/06-https-listener-config.png)

**7. Listener created: HTTP:80 and HTTPS:443 both forward to the Lambda target group for now (account ID redacted)**
![HTTPS listener added](screenshots/07-https-listener-added.png)

**8. The HTTP:80 default action changed to a 301 redirect to HTTPS**
![Redirect](screenshots/08-http-redirect-301.png)

**9. HTTP:80 saved: default action "Redirect to HTTPS://#{host}:443/#{path}?#{query}", status code HTTP_301 (account ID redacted)**
![HTTP:80 redirect saved](screenshots/09-http80-redirect-saved.png)

**10. Task 5: apex A record, Alias to the dualstack ALB name**
![Alias record](screenshots/10-create-alias-a-record.png)

**11. The hosted zone after: NS, SOA, the validation CNAME and the A alias**
![Hosted zone after](screenshots/11-hosted-zone-after.png)

**12. Task 6: `https://bootcamp-student[X].com` returns the Lambda response with `"protocol": "https"` (Chrome this time; the Task 1 test used Safari)**
![Domain HTTPS](screenshots/12-domain-https-secure.png)

**13. CloudShell: `curl -s https://bootcamp-student[X].com` returns the Lambda JSON with `"protocol": "https"` and `curl/8.21.0` as the user agent. `curl -I http://...` returns `301 Moved Permanently` from `awselb/2.0` with `Location: https://bootcamp-student[X].com:443/`. (The `bad range` error in between is a typo: I typed the literal `[ALB DNS name]` placeholder, and curl reads square brackets as a URL range.)**
![curl redirect](screenshots/13-curl-http-301.png)

**14. Task 7 gotcha: typing `https://bootcamp-student[X].com` in the Host header value gives "Invalid condition value"**
![Invalid host header value](screenshots/14-host-header-invalid-value.png)

**15. Task 7: review before creating the rule on HTTPS:443: Host header = the bare domain, forward to `customdomain-lambda-tg-l2`, priority 1**
![Host header rule](screenshots/15-host-header-rule.png)

**16. Rule created: rule 1 (Host header) added, the default action still forwards to the target group for now (account ID redacted)**
![Rule created](screenshots/16-rule-created-default-still-forward.png)

**17. Edit listener: the HTTPS:443 default action set to Return fixed response, 403, text/plain**
![Fixed response](screenshots/17-default-fixed-response-403.png)

**18. Both listeners at the end: HTTP:80 redirects to HTTPS with a 301, HTTPS:443 has 2 rules (the Host header rule plus a default that returns a fixed 403 with "Access denied. Please use the custom domain.") (account ID redacted)**
![Listeners final](screenshots/18-listeners-final.png)

**19. Final test: `curl -ik https://[ALB DNS name]` gets `HTTP/2 403` and "Access denied. Please use the custom domain." from `awselb/2.0` (the domain itself works, see screenshots 14 and 16)**
![Final test](screenshots/19-final-domain-vs-alb-403.png)

**20. The same 403 in a browser, from the ALB's own address**
![Browser 403](screenshots/20-browser-alb-403.png)

## Well-Architected pillars
- **Security:** traffic between users and the ALB is encrypted with TLS, plain HTTP can't be used because it is redirected, and the Host header rule stops anyone reaching the app through the raw ALB name. The certificate's private key never leaves ACM.
- **Reliability:** ACM renews the certificate automatically as long as the validation CNAME stays in Route 53, so an expired certificate can't take the site down. The alias record follows the ALB's changing IP addresses.
- **Operational Excellence:** TLS is configured in one place (the ALB) instead of on every backend, and the backend (Lambda) needs no certificate or code change.
- **Performance Efficiency:** the ALB does the TLS handshake and decryption, so Lambda only handles the request itself.
- **Cost Optimization:** public ACM certificates used with an ALB are free, alias queries to an ALB are free, and blocked requests are answered by the ALB without invoking (or billing) Lambda.

## What I learned
- **You can't get a valid certificate for the ALB's own DNS name.** ACM only issues certificates for domains you can prove you own, and `elb.amazonaws.com` belongs to AWS. So HTTPS with a padlock needs a custom domain in front of the ALB.
- **DNS validation is a CNAME that proves ownership.** ACM checks that the `_xxxx` record exists. Leaving it in place is what lets ACM renew the certificate automatically (it starts trying 60 days before expiry). Email validation needs a person to approve each renewal.
- **A new certificate isn't eligible for renewal yet.** Right after the request, ACM showed *In use: No* and *Renewal eligibility: Ineligible*. ACM only renews certificates that are in use by an integrated service (here, the ALB listener), so attaching it in Task 4 is what makes managed renewal apply.
- **The private key never leaves AWS.** Key source *AWS managed* and *Export option: Disabled* mean you can use the certificate on ALB, CloudFront and API Gateway, but you can't download it for your own server.
- **The security policy decides which TLS versions and ciphers the ALB accepts.** The recommended policy, `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`, allows only TLS 1.3 and 1.2 with a restricted set of ciphers ("Res"), and adds post-quantum key exchange ("PQ"). Older clients that only speak TLS 1.0 or 1.1 can't connect.
- **The certificate is the listener's *default*.** The ALB uses SNI (Server Name Indication) to choose a certificate when a listener has several. The default certificate is the one sent when the client doesn't send a name or no certificate matches it, so one HTTPS listener can serve several domains.
- **TLS termination at the ALB.** The ALB decrypts HTTPS and forwards the request to Lambda inside AWS, so the backend never handles certificates. The other model, passthrough, sends encrypted traffic straight to the backend (an NLB TCP listener can do this).
- **How the Lambda knows the protocol.** The ALB adds an `x-forwarded-proto` header (`http` or `https`) to every request it forwards. (I didn't see the function code, so this is how ALB behaves rather than something I checked in the Lambda.)
- **This Lambda reads the User-Agent correctly.** In Level 1, `user_agent` was always "Unknown". The Level 2 function returned my real Safari User-Agent, so it reads the header ALB actually sends (lowercase `user-agent`). That fits my Level 1 guess that the Level 1 code looked the header up with the wrong case.
- **The redirect runs before the rules.** HTTP:80 has no forward action any more, so every HTTP request becomes HTTPS first and then goes through the HTTPS listener's rules, including the Host header check.
- **ALB won't let you build a redirect loop.** The Redirect to URL form warns that HTTPS can't be redirected to HTTP, and that at least one of protocol, port, host or path must change. Leaving *URI parts* on keeps the original host, path and query (`#{host}`, `#{path}`, `#{query}`), so `http://site/page?x=1` goes to `https://site/page?x=1`.
- **A Host header is a bare domain name, not a URL.** In the rule I first pasted `https://bootcamp-student[X].com` and the console showed "Invalid condition value". The Host header only carries the host name (`bootcamp-student[X].com`), with no `https://` and no path, and it only allows letters, digits and a few special characters.
- **The redirect response comes from the ALB itself.** `Server: awselb/2.0` on the 301 shows the load balancer answered without calling Lambda, and the `Location` header keeps the host and path and adds the port explicitly (`https://bootcamp-student[X].com:443/`) because the redirect rule has Port 443 set.
- **curl treats `[` as a URL range.** Typing the placeholder `https://[ALB DNS name]` gave `curl: (3) bad range`. Use the real DNS name, or quote the URL / use `-g`.
- **301 is permanent and browsers cache it.** Once a browser has seen the 301, it may go straight to HTTPS next time without asking the ALB.

## Interview questions
- **Can you use HTTPS with just the ALB URL?** Not with a trusted certificate: certificates can only be issued for a domain you own, so you put a custom domain (Route 53 or another DNS provider) in front of the ALB.
- **SSL vs TLS?** TLS is the modern successor; SSL is deprecated but the name stuck. Both encrypt data in transit, authenticate the server and detect tampering.
- **SSL termination vs passthrough?** Termination: the load balancer decrypts and the backend needs no certificate (what this lab built). Passthrough: the backend decrypts, for end-to-end encryption or strict compliance.
- **What happens when a certificate expires?** Browsers show "Your connection is not private" and API clients fail. ACM prevents it with managed renewal, as long as DNS validation stays in place.
