# Publishing this portfolio on GitHub

## Option A: in the browser (no installs)
1. Sign in to github.com and click **New repository**. Name it `AWS-Cloud-Portfolio`, set it to **Public**, and create it.
2. Click **uploading an existing file**, drag in everything from this folder (keep the folder structure), and **Commit changes**.
3. Add your own screenshots to each project's `screenshots/` folder and uncomment the image lines in that README.

## Option B: with git
```bash
cd github-portfolio
git init && git add . && git commit -m "Add cloud projects portfolio"
git branch -M main
git remote add origin https://github.com/Rhamilton14/AWS-Cloud-Portfolio.git
git push -u origin main
```

## Make it stand out
- **Pin the repo** on your profile (Profile → Customize your pins).
- **Profile README:** create a repo named exactly your username and paste in `PROFILE-README.md`.
- **Screenshots:** crop out account IDs, ARNs and anything with your name or email.
- Add the **topics** `aws`, `cloud`, `serverless` and `portfolio` on the repo page (gear icon next to About).
