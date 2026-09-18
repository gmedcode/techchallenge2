# 🚀 Tech Challenge: Containerized Flask App on AWS EKS with CI/CD

![Terraform](https://img.shields.io/badge/IaC-Terraform-844FBA?logo=terraform&logoColor=white)
![Docker](https://img.shields.io/badge/Container-Docker-2496ED?logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Orchestration-EKS-326CE5?logo=kubernetes&logoColor=white)
![Jenkins](https://img.shields.io/badge/CI%2FCD-Jenkins-D24939?logo=jenkins&logoColor=white)
![ArgoCD](https://img.shields.io/badge/GitOps-Argo%20CD-EF7B4D?logo=argo&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white)

A simple Flask **"Hello, World!"** application, containerized with Docker, deployed to AWS EKS via Terraform, and continuously deployed using **two parallel CI/CD approaches**:

| Branch | CI | CD |
|---|---|---|
| `main` | Jenkins | Jenkins (`helm upgrade`) |
| `gitops` | GitHub Actions (OIDC) | Argo CD (auto-sync) |

> 📌 **Placeholder convention:** anywhere you see `<YOUR_ACCOUNT_ID>` or `<YOUR_GITHUB_USERNAME>` in this README or the repo's code, substitute your own AWS account ID (`aws sts get-caller-identity`) or GitHub username/org. These are left as placeholders intentionally, since this repo is public.

---

## 🏗️ Architecture

```
Developer → git push → Jenkins/GitHub Actions → Docker build → ECR
                                                                  │
                                          EKS Cluster ← Helm/Argo CD deploy
                                                │
                                    AWS Load Balancer Controller
                                                │
                                     ALB (public) → Flask app pods
```

- **Terraform** provisions: VPC (public/private subnets), EKS cluster, managed node group (`t3.small`, autoscaling 1→4), ECR repository, IAM roles for the ALB Controller and CI/CD tooling, and (on `main`) a Jenkins EC2 server
- **Kubernetes/Helm** deploys the app as a Deployment + Service + HPA + Ingress
- **AWS Load Balancer Controller** watches the Ingress and provisions a real Application Load Balancer (ALB)
- **HPA** scales pods 1→3 based on 50% CPU *or* 50% memory utilization (requires `metrics-server` — see step 4)

---

## ✅ Prerequisites

- AWS CLI, configured with credentials that have permissions for EKS, EC2, IAM, VPC, and ECR
- Terraform (>= 1.5.0)
- kubectl
- Helm (v3)
- Docker
- Your AWS account ID (`aws sts get-caller-identity`) and a GitHub username/org

---

## 📁 Repository Structure

```
techchallenge2/
├── webapp/              # Flask app source + Dockerfile
├── terraform/           # All infrastructure as code
├── flask-app/           # Helm chart for the application
├── Jenkinsfile          # Jenkins pipeline (main branch)
├── .github/workflows/   # GitHub Actions CI (gitops branch only)
├── argocd/               # Argo CD Application manifest (gitops branch only)
```

---

## 🛠️ Setup & Deployment Steps

### 1. Clone the repository
```bash
git clone https://github.com/gmedcode/techchallenge2.git
cd techchallenge2
```

### 2. Provision infrastructure with Terraform
```bash
cd terraform
terraform init
terraform apply -var="github_username=<YOUR_GITHUB_USERNAME>"
```
Creates the VPC, EKS cluster, node group, ECR repository, and (on `main`) the Jenkins EC2 server. Takes ~15–20 minutes, mostly EKS cluster creation.

> `github_username` is only used for the GitHub Actions IAM trust policy on the `gitops` branch. On `main` you can pass any value — it isn't referenced there. Running terraform apply with -> -var="github_username=<YOUR_GITHUB_USERNAME>" <- ensures you don't have to type your github username each time. This variable was added to ensure communication with gitops and IAM trust policy.

### 3. Connect kubectl to the new cluster
```bash
aws eks update-kubeconfig --region us-east-1 --name hello-world-cluster
kubectl get nodes
```

### 4. Install cluster-level prerequisites
```bash
# metrics-server — required for the HPA to read CPU/memory usage
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# AWS Load Balancer Controller — required for the Ingress to provision a real ALB
helm repo add eks https://aws.github.io/eks-charts
helm repo update
kubectl create serviceaccount aws-load-balancer-controller -n kube-system
kubectl annotate serviceaccount aws-load-balancer-controller -n kube-system \
  eks.amazonaws.com/role-arn=$(terraform output -raw alb_controller_role_arn)
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=hello-world-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 \
  --set vpcId=$(terraform output -raw vpc_id)
```

### 5. Build and push the Docker image
```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <YOUR_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

cd ../webapp
docker build --platform linux/amd64 -t flask-hello-world .
docker tag flask-hello-world:latest <YOUR_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/flask-hello-world:latest
docker push <YOUR_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/flask-hello-world:latest
```
> ⚠️ `--platform linux/amd64` is required if building on an Apple Silicon (ARM64) Mac — EKS nodes run x86_64, and images built without this flag will fail to pull with a `no match for platform` error.

### 6. Deploy the app via Helm
```bash
cd ../flask-app
helm install flask-app . --set image.repository=<YOUR_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/flask-hello-world
```

### 7. Get the app's URL
```bash
kubectl get ingress
```
The `ADDRESS` column shows the ALB's DNS name once provisioned (1–2 minutes). Visit it in a browser or `curl` it — you should see **"Hello, World!"**

---

## 🧱 Terraform Explanation

| File | Purpose |
|---|---|
| `provider.tf` | AWS + TLS provider configuration |
| `variables.tf` | Input variables (region, cluster name, instance type, GitHub username) |
| `vpc.tf` | VPC, public/private subnets across 2 AZs, NAT Gateway, route tables |
| `key.tf` | SSH key pair (generated by Terraform, private key saved locally, gitignored) |
| `eks.tf` | EKS cluster, IAM roles for control plane and worker nodes, managed node group (`t3.small`, autoscaling 1→4), OIDC provider (for IRSA) |
| `ecr.tf` | ECR repository for the Docker image (`force_delete = true` for a clean `terraform destroy`) |
| `alb-controller-iam.tf` | IAM policy + role for the AWS Load Balancer Controller, trusted via the cluster's OIDC provider |
| `jenkins.tf` *(`main` only)* | Jenkins EC2 server, security group, IAM role with ECR/EKS permissions |
| `githubactions-am.tf` *(`gitops` only)* | IAM OIDC provider + role for GitHub Actions, scoped to this repo via a `sub` trust condition |

**Key design decisions:**
- Worker nodes sit in **private subnets** (best practice — not directly internet-facing); only the ALB sits in public subnets
- The EKS node group's AMI type is explicitly set to `AL2_x86_64` — omitting it can cause an `InvalidParameterException` on some Kubernetes versions
- GitHub Actions authenticates via **OIDC federation**, not long-lived access keys — no AWS credentials are stored as GitHub Secrets besides the role ARN itself

---

## 🔧 Jenkins Pipeline Explanation (`main` branch)

Jenkins runs on a dedicated EC2 instance (`t3.micro`), with Jenkins itself running inside a Docker container on that host.

**Pipeline stages:**
1. **Checkout** — pulls the latest code from this repo
2. **Build Docker Image** — builds the Flask app's image, tagged with the Jenkins build number
3. **Push to ECR** — authenticates via the EC2 instance's IAM role (no stored credentials) and pushes the image
4. **Deploy to EKS** — runs `helm upgrade --install`, pointing at the newly built image
5. **Verify Deployment** — confirms the rollout succeeded and prints the Ingress address

The Jenkins EC2 instance's IAM role has ECR push and EKS describe permissions, and is mapped into the cluster's `aws-auth` ConfigMap with `system:masters` group access so it can run `kubectl`/`helm` commands.

`AWS_ACCOUNT_ID` is set as a Jenkins **Global Environment Variable** (Manage Jenkins → System → Global properties) rather than hardcoded in the Jenkinsfile — keeping the committed pipeline code account-agnostic.

**Accessing Jenkins:**
```bash
terraform output jenkins_public_ip
ssh -i terraform/hello-world-cluster-key.pem ec2-user@<jenkins-ec2-public-ip>
sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```
Then visit `http://<jenkins-ec2-public-ip>:8080`.

**Inside the Jenkins container**, install the required CLI tools before the pipeline can run:
```bash
sudo docker exec -it jenkins bash
apt-get update && apt-get install -y curl unzip docker.io

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && ./aws/install

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl /usr/local/bin/

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Then, in the Jenkins UI: create a Pipeline job → *Pipeline script from SCM* → Git → this repo's URL → branch `main` → script path `Jenkinsfile`.

---

## 🔄 GitOps Alternative (`gitops` branch)

This branch demonstrates an alternative CI/CD approach using **GitHub Actions** for CI and **Argo CD** for CD, in place of Jenkins.

- **GitHub Actions** (`.github/workflows/ci.yml`) builds and pushes the Docker image to ECR on every push to `gitops`, authenticating via OIDC federation
- **Argo CD** continuously watches this repo's `flask-app/` Helm chart on `gitops`. When it detects a change, it auto-syncs the cluster to match (`syncPolicy.automated`, `selfHeal: true`)

> 🔀 Jenkins **pushes** changes to the cluster via an explicit pipeline step. Argo CD **pulls** changes by continuously reconciling the cluster against git. This branch is a practice demonstration of the GitOps pattern — in a real-world scenario, Jenkins and Argo CD wouldn't typically run simultaneously against the same live cluster, since both would compete to manage the same resources.

**GitHub Actions secret setup:**
`Settings → Secrets and variables → Actions` → add `AWS_ROLE_ARN` = output of `terraform output github_actions_role_arn`

**Argo CD setup:**
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl port-forward svc/argocd-server -n argocd 8081:443
# https://localhost:8081 — username: admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Edit the placeholder account ID in argocd/application.yaml first — do not commit the real value
kubectl apply -f argocd/application.yaml
```

---

## 🐛 Troubleshooting Notes (issues hit during this build)

| Issue | Cause | Fix |
|---|---|---|
| EKS node group `InvalidParameterException` | `ami_type` left implicit | Explicitly set `ami_type = "AL2_x86_64"` |
| `ImagePullBackOff` — "no match for platform" | Built on Apple Silicon without a platform flag | Add `--platform linux/amd64` to `docker build` |
| `docker: not found` in Jenkins pipeline | `jenkins/jenkins:lts` doesn't ship the Docker CLI | Install `docker.io` inside the Jenkins container |
| GitHub Actions `AssumeRoleWithWebIdentity` denied | GitHub appends `@<id>` to the `sub` claim | Wildcard the trust policy: `repo:<user>*/<repo>*:*` |
| Argo CD "Degraded" with a healthy pod | `metrics-server` not installed by default on EKS | `kubectl apply` the metrics-server manifest |
| Argo CD pods `Pending`/`CrashLoopBackOff` | Single `t3.small` node too small | Temporarily scale node group to 2 desired nodes |
| `terraform destroy` fails on VPC/subnets | ALB Controller creates resources outside Terraform's knowledge | Delete the Ingress (or the ALB/security groups manually) first |

---

## 🧹 Teardown

```bash
cd terraform
terraform destroy -var="github_username=<YOUR_GITHUB_USERNAME>"
```
If the AWS Load Balancer Controller created an ALB, delete the Ingress first (`kubectl delete ingress flask-app`) — or, if the cluster's already gone, manually delete the leftover ALB and security groups (`aws elbv2 delete-load-balancer` / `aws ec2 delete-security-group`) to avoid VPC/subnet dependency errors.
