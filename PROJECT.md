# SRE Portfolio Project — Highly Available Node App on AWS via Terraform

## Purpose

A portfolio project to demonstrate Site Reliability Engineering fundamentals for a
2–3 year SRE/DevOps role. The application itself is deliberately trivial; the value
is in the **delivery**: infrastructure as code, a multi-AZ highly-available
architecture, and a CI/CD pipeline that gates and applies infrastructure changes.

This project is intentionally the "proper deployment process" the author has not had
in prior solo roles — that gap-closing is part of the point.

## Skills demonstrated (mapped to job requirements)

- **AWS** — VPC, ALB, Auto Scaling Group, EC2, security groups, IAM
- **Terraform / Infrastructure as Code** — entire environment defined in code
- **Git** — clean, incremental commit history telling a coherent story
- **CI/CD** — GitHub Actions pipeline gating `terraform plan` on PRs, applying on merge

## Architecture

A small Node/Express app running on EC2 instances in an Auto Scaling Group, behind
an Application Load Balancer, spread across two Availability Zones for high
availability. No single point of failure in the compute or load-balancing layer.

```
Internet
   │
   ▼
Application Load Balancer  (spans 2 AZs)
   │
   ▼
Auto Scaling Group  →  EC2 (t3.micro) in AZ-a
                    →  EC2 (t3.micro) in AZ-b
```

### Infrastructure (all in Terraform, in /infra)
- VPC with two public subnets across two Availability Zones
- Application Load Balancer spanning both subnets
- Auto Scaling Group running the Node app on t3.micro instances (free-tier eligible)
- Security groups: ALB accepts HTTP from the internet; instances accept traffic only from the ALB
- IAM role for the instances
- Boot script (EC2 user data) that installs Node, pulls the app, and starts it — this
  is the bridge between the infra layer and the app layer

## Scope discipline — deliberate cuts (these are NEXT STEPS, not failures)

- **No RDS** — a running Multi-AZ DB costs money and adds setup time. Document where it
  would slot in. Talk about it in interviews rather than building it for v1.
- **No custom domain / HTTPS** — use the ALB's default DNS name. Route 53 + ACM is a v2.
- **No containers / Kubernetes** — "nice to have" on the posting, not required. EC2 + ASG
  is the required-list path and is simpler.

Knowing what to leave out is itself a senior SRE trait; the README should frame these
as documented, intentional next steps.

## Repo structure (monorepo)

```
my-sre-project/
├── app/                    # the Node project
│   ├── package.json
│   └── server.js
├── infra/                  # the Terraform
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── .github/
│   └── workflows/
│       └── deploy.yml      # CI/CD pipeline
├── .gitignore
└── README.md
```

## Build order (target: a few evenings)

1. **App + repo.** Write the Express app, run locally, push to a fresh GitHub repo
   under `app/`. (Plays to existing Node strength — build momentum first.)
2. **Terraform core.** VPC, subnets, security groups. `terraform apply` manually from
   the laptop. Goal: see infra you defined in code appear in the AWS console.
3. **ALB + ASG.** Wire the app onto instances behind the load balancer. Hit the ALB
   DNS name in a browser. Kill an instance in the console and watch the ASG replace it.
4. **Pipeline + docs.** Move `apply` off the laptop into GitHub Actions, gated on PRs.
   Write the README with an architecture diagram and the deliberate cuts as next steps.

## Node app spec (Evening 1)

Functional:
1. `GET /` — returns a simple HTML page. Display the serving instance's hostname
   (`os.hostname()`, built-in, no dependency) so multi-instance load balancing is
   visible by refreshing.
2. `GET /health` — returns HTTP 200 with JSON `{"status":"ok"}`. This is the contract
   the ALB and ASG use to decide if an instance is alive. Must be fast, dependency-free,
   and never do anything heavy. (A health check that depends on a DB will kill healthy
   instances when the DB hiccups — keep it independent.)
3. Listen on a configurable port via `process.env.PORT`, defaulting to 3000.

Structural:
4. `package.json` with a `start` script (`node server.js`). The boot script runs
   `npm install` then `npm start`.
5. Minimal dependencies — Express only, ideally.
6. Runs cleanly from a fresh clone: `cd app && npm install && npm start` with zero
   manual steps. Test by deleting node_modules and re-running.
7. `.gitignore` excluding `node_modules` (and later Terraform `.terraform/` and state).

Out of scope: no database, auth, sessions, front-end framework, or build step.

Definition of done (Evening 1): `npm start` locally, `localhost:3000/` shows the page
with hostname, `localhost:3000/health` returns the JSON, all pushed to GitHub under `app/`.

## Operational guardrails (do these immediately)

- Set an **AWS billing alert** (a few-dollars threshold) the moment the account exists.
- Run `terraform destroy` whenever not actively working — IaC means tearing down and
  rebuilding in minutes. Use it to stay near-free.
- For the GitHub Actions → AWS connection, use **short-lived OIDC credentials**, not
  long-lived access keys pasted into secrets. Correct security practice and good
  interview material.

## The thing that makes it a portfolio piece

The README and the Git history. A clean, incremental commit history plus a README
explaining *why* each choice was made is what separates "I followed a tutorial" from
"I understand what I built."