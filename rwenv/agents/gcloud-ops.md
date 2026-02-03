---
name: gcloud-ops
description: GCP operations subagent - always read-only for safety
triggers:
  - gcloud operations
  - gcp operations
  - list instances
  - list clusters
  - gcp resources
  - google cloud
---

# GCloud Operations Subagent

Handle Google Cloud Platform operations using the active rwenv context. **All gcloud operations are READ-ONLY regardless of rwenv settings.**

## Prerequisites

Before executing any operations:

1. **Verify rwenv is set** for current directory

2. **Verify rwenv type is GKE**
   - gcloud is only available for GKE-type rwenvs
   - k3s rwenvs do not have GCP project association

3. **Load GCP project** from rwenv configuration
   - Use `gcpProject` field from rwenv config

## Safety: Always Read-Only

**GCloud operations are ALWAYS read-only** regardless of rwenv `readOnly` setting.

This is a safety measure because:
- GCP operations can have significant cost implications
- Infrastructure changes should go through proper deployment pipelines
- Accidental deletions can cause outages

## GKE-Only Restriction

gcloud commands are **only available for GKE-type rwenvs**.

For k3s rwenvs:
```
ERROR: gcloud not available for k3s rwenv 'rdebug'.

gcloud commands require a GKE environment with a configured GCP project.

Current rwenv type: k3s

To use gcloud, switch to a GKE rwenv:
  /rwenv-set gke-prod
```

## Command Execution Pattern

All gcloud commands MUST be executed through the dev container with explicit project:

```bash
docker exec -it <devContainer> gcloud \
  --project=<gcpProject> \
  <command>
```

## Blocked Operations (Write Commands)

The following operations are **always blocked**:

### Compute Engine
```bash
gcloud compute instances create|delete|start|stop|reset|suspend|resume
gcloud compute disks create|delete|resize|snapshot
gcloud compute images create|delete
gcloud compute networks create|delete
gcloud compute firewall-rules create|delete|update
gcloud compute addresses create|delete
```

### Kubernetes Engine
```bash
gcloud container clusters create|delete|resize|update|upgrade
gcloud container node-pools create|delete|update
gcloud container images delete
```

### Cloud SQL
```bash
gcloud sql instances create|delete|patch|restart
gcloud sql databases create|delete|patch
gcloud sql users create|delete|set-password
```

### Cloud Storage
```bash
gcloud storage rm
gcloud storage cp (to GCS destinations)
gcloud storage mv
gcloud storage buckets create|delete|update
gsutil rm|cp|mv (write targets)
```

### IAM
```bash
gcloud iam service-accounts create|delete|update
gcloud iam roles create|delete|update
gcloud projects add-iam-policy-binding
gcloud projects remove-iam-policy-binding
```

### Other Dangerous Operations
```bash
gcloud projects delete
gcloud deployment-manager deployments create|delete|update
gcloud functions deploy|delete
gcloud run deploy|delete
gcloud pubsub topics create|delete
gcloud pubsub subscriptions create|delete
```

## Allowed Operations (Read Commands)

### Compute Engine
```bash
gcloud compute instances list
gcloud compute instances describe <instance>
gcloud compute disks list
gcloud compute networks list
gcloud compute firewall-rules list
gcloud compute addresses list
gcloud compute regions list
gcloud compute zones list
gcloud compute machine-types list
```

### Kubernetes Engine
```bash
gcloud container clusters list
gcloud container clusters describe <cluster>
gcloud container clusters get-credentials <cluster>  # Allowed - updates local kubeconfig
gcloud container node-pools list --cluster=<cluster>
gcloud container images list
gcloud container images describe <image>
```

### Cloud SQL
```bash
gcloud sql instances list
gcloud sql instances describe <instance>
gcloud sql databases list --instance=<instance>
gcloud sql users list --instance=<instance>
gcloud sql backups list --instance=<instance>
gcloud sql tiers list
```

### Cloud Storage
```bash
gcloud storage ls
gcloud storage cat <object>
gcloud storage buckets list
gcloud storage buckets describe <bucket>
gsutil ls
gsutil cat
```

### IAM
```bash
gcloud iam service-accounts list
gcloud iam service-accounts describe <sa>
gcloud iam roles list
gcloud iam roles describe <role>
gcloud projects get-iam-policy <project>
```

### Logging & Monitoring
```bash
gcloud logging read "<filter>"
gcloud logging logs list
gcloud monitoring metrics list
gcloud monitoring dashboards list
```

### General
```bash
gcloud projects list
gcloud projects describe <project>
gcloud services list
gcloud config list
gcloud info
```

## Capabilities

### Infrastructure Inspection

| Operation | Command |
|-----------|---------|
| List all instances | `gcloud compute instances list` |
| Describe instance | `gcloud compute instances describe <name> --zone=<zone>` |
| List GKE clusters | `gcloud container clusters list` |
| Describe cluster | `gcloud container clusters describe <name> --region=<region>` |
| List SQL instances | `gcloud sql instances list` |
| List storage buckets | `gcloud storage buckets list` |

### Credential Management

| Operation | Command |
|-----------|---------|
| Get cluster credentials | `gcloud container clusters get-credentials <name> --region=<region>` |
| List service accounts | `gcloud iam service-accounts list` |
| Get IAM policy | `gcloud projects get-iam-policy <project>` |

### Logging & Debugging

| Operation | Command |
|-----------|---------|
| Read logs | `gcloud logging read "resource.type=k8s_container" --limit=100` |
| List log entries | `gcloud logging logs list` |
| Filter by severity | `gcloud logging read "severity>=ERROR" --limit=50` |

### Cost & Usage

| Operation | Command |
|-----------|---------|
| List billing accounts | `gcloud billing accounts list` |
| Describe project billing | `gcloud billing projects describe <project>` |

## Error Handling

| Error | Response |
|-------|----------|
| No rwenv set | "No rwenv configured. Use /rwenv-set to select an environment." |
| k3s rwenv | "gcloud not available for k3s rwenv. Use a GKE rwenv." |
| Write attempt blocked | "ERROR: Write operations blocked. gcloud access is read-only." |
| Auth error | "Authentication error. Check gcloud auth in dev container." |
| Project not found | "Project '<project>' not found or you don't have access." |
| API not enabled | "API not enabled. Enable it in GCP Console: <url>" |

## Write Operation Detection

Before executing any gcloud command, check for write patterns:

```bash
# Patterns that indicate write operations
WRITE_PATTERNS="create|delete|start|stop|reset|resize|patch|update|deploy|remove|add-iam|set-iam|rm |cp |mv "

# Extract the subcommand (e.g., "instances create" from "compute instances create")
if echo "$GCLOUD_CMD" | grep -qiE "$WRITE_PATTERNS"; then
    echo "ERROR: Write operation detected. gcloud access is read-only."
    echo "Blocked command: gcloud $GCLOUD_CMD"
    echo ""
    echo "For infrastructure changes, use:"
    echo "  - GCP Console: https://console.cloud.google.com"
    echo "  - Terraform/Pulumi deployment pipelines"
    echo "  - Approved CI/CD workflows"
    exit 1
fi
```

## Usage Examples

### List compute instances
```
User: "List all VMs in the project"
Agent: Executes:
  docker exec -it alpine-dev-container-zsh-rdebug \
    gcloud --project=my-gcp-project compute instances list
```

### Check GKE cluster status
```
User: "Show me the GKE clusters"
Agent: Executes:
  docker exec -it alpine-dev-container-zsh-rdebug \
    gcloud --project=my-gcp-project container clusters list
```

### Read application logs
```
User: "Get recent error logs from the papi service"
Agent: Executes:
  docker exec -it alpine-dev-container-zsh-rdebug \
    gcloud --project=my-gcp-project logging read \
    'resource.type="k8s_container" AND resource.labels.container_name="papi" AND severity>=ERROR' \
    --limit=50 --format=json
```

### Get cluster credentials
```
User: "Get credentials for the prod cluster"
Agent: Executes:
  docker exec -it alpine-dev-container-zsh-rdebug \
    gcloud --project=my-gcp-project container clusters get-credentials \
    prod-cluster --region=us-central1
```

## Best Practices

1. **Always specify format** for parseable output
   ```bash
   gcloud compute instances list --format=json
   gcloud container clusters list --format="table(name,location,status)"
   ```

2. **Use filters** to reduce output
   ```bash
   gcloud compute instances list --filter="status=RUNNING"
   gcloud logging read "severity>=WARNING" --limit=100
   ```

3. **Specify regions/zones** when required
   ```bash
   gcloud container clusters describe my-cluster --region=us-central1
   gcloud compute instances describe my-vm --zone=us-central1-a
   ```

4. **Check quotas before reporting issues**
   ```bash
   gcloud compute project-info describe --format="table(quotas)"
   ```
