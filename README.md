
# Kubernetes Cluster on AWS Using Terraform

Provision a Kubernetes cluster on AWS using **Terraform**, with four EC2 instances, private worker and control-plane nodes, a Bastion Host, and a Squid proxy server for outbound internet access.

This project automates the infrastructure provisioning and Kubernetes node configuration required to build a Kubernetes cluster using kubeadm, kubelet, kubectl, containerd, and Cilium as the Container Network Interface (CNI).

The infrastructure is designed with a focus on **automation, network isolation, security, and Kubernetes cluster administration**.

## Project Overview
This project provisions four EC2 instances inside a custom AWS VPC and configures them for a Kubernetes cluster.

### Key Features
- **Infrastructure as Code:** Provision AWS infrastructure using Terraform.
- **Four EC2 Instances:** Deploy one Bastion Host, one Kubernetes control-plane node, and two worker nodes.
- **Custom VPC:** Create a dedicated VPC and subnet configuration for the cluster.
- **Network Security:** Configure security groups to control communication between instances.
- **Private Kubernetes Nodes:** Keep the control-plane and worker nodes inaccessible directly from the public internet.
- **Bastion Host:** Provide a controlled entry point for administrative access.
- **Squid Proxy Server:** Provide outbound internet access to private nodes through a proxy.
- **Container Runtime:** Install and configure containerd.
- **Kubernetes Components:** Install and configure kubeadm, kubelet, and kubectl.
- **Cilium CNI:** Configure Cilium for Kubernetes networking.
- **Automated Deployment:** Use Terraform to provision the infrastructure.


## Architecture

The infrastructure consists of four EC2 instances deployed inside a custom AWS VPC.

                         ┌─────────────────────────┐
                         │        Internet         │
                         └────────────┬────────────┘
                                      │
                         ┌────────────▼────────────┐
                         │       AWS VPC            │
                         │                          │
                         │  ┌────────────────────┐  │
                         │  │    Bastion Host     │  │
                         │  │   Public Access     │  │
                         │  │                    │  │
                         │  │   Squid Proxy       │  │
                         │  └─────────┬──────────┘  │
                         │            │             │
                         │     Private Network      │
                         │            │             │
                         │  ┌─────────▼──────────┐  │
                         │  │ Kubernetes Master  │  │
                         │  │   Control Plane    │  │
                         │  └────────────────────┘  │
                         │                          │
                         │  ┌────────────────────┐  │
                         │  │    Worker Node 1   │  │
                         │  └────────────────────┘  │
                         │                          │
                         │  ┌────────────────────┐  │
                         │  │    Worker Node 2   │  │
                         │  └────────────────────┘  │
                         │                          │
                         └──────────────────────────┘
**Note:** The diagram represents the logical architecture. The actual public/private subnet layout, Squid deployment location, and routing configuration depend on the Terraform implementation.


### EC2 Instance Roles

| Instance	| Role	| Network Access | Responsibilities |
| :--- | :---: | :--- | :---: |
| bastion_host | Bastion Host / Proxy |	Public entry point | Administrative access and Squid proxy services |
| master | Kubernetes Control Plane | Private | Manages the Kubernetes cluster |
| worker-1 | Kubernetes Worker | Private | Runs application workloads |
| worker-2 | Kubernetes Worker | Private | Runs application workloads |

### Network Design

The cluster uses a custom AWS VPC with security groups to control network communication.

- The Bastion Host acts as the administrative entry point.
- The master and worker nodes do not have direct public internet access.
- Private nodes use the Squid proxy to access external resources, such as package repositories and container registries.
- Security groups restrict inbound and outbound traffic according to the configured rules.
- Kubernetes nodes communicate over the private network.

**Important:** A Squid proxy provides application-level outbound HTTP/HTTPS access. It does not automatically provide unrestricted internet connectivity or replace a NAT gateway for arbitrary network traffic.

## Technology Stack

| Technology | Purpose |
| :--- | :---: |
| AWS EC2 | Compute instances |
| Amazon VPC | Network isolation |
| AWS Security Groups | Instance-level traffic control |
| Terraform | Infrastructure provisioning |
| Linux | Operating system for Kubernetes nodes |
| containerd | Container runtime |
| kubeadm | Kubernetes cluster bootstrapping |
| kubelet | Kubernetes node agent |
| kubectl | Kubernetes command-line interface |
| Cilium | Kubernetes networking and CNI |
| Squid | HTTP/HTTPS proxy for private nodes |

## Prerequisites

Before deploying the project, ensure you have the following:

- An AWS account.
- An IAM identity with the permissions required to create and manage the AWS resources defined in the Terraform configuration.
- AWS Access Key ID and Secret Access Key, if using IAM user access keys.
- [Terraform installed on your local machine.](https://developer.hashicorp.com/terraform/install)
- [AWS CLI installed](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- Git installed.
- SSH key pair or another supported method for securely accessing the EC2 instances.
- Basic knowledge of AWS networking, Terraform, Linux, and Kubernetes.

### Verify Installed Tools

Check whether Terraform, AWS CLI, and Git are installed:

```

terraform -version
aws --version
git --version

```
Configure the AWS region and verify your AWS identity:

```

aws configure

aws sts get-caller-identity

```

If your environment already uses an AWS IAM role, IAM Identity Center, or another supported credential provider, you can use that instead of long-lived access keys.

## Deployment Guide

Follow these steps to deploy the infrastructure.

### Step 1: Clone the Repository

Clone the repository and navigate into the project directory.

```

git clone <YOUR_GITHUB_REPOSITORY_URL>
cd <YOUR_PROJECT_DIRECTORY>

```

Replace the placeholders with your actual GitHub repository URL and project directory.

### Step 2: Create the Environment File

Copy the example environment file:

```

cp .env.example .env

```

Open .env and configure your AWS credentials if the project expects credentials through these environment variables.

```

nano .env

```

Example .env:

```

export AWS_ACCESS_KEY_ID="YOUR_AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="YOUR_AWS_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="ap-south-1"

```

Replace the example values with your own configuration.

### Step 3: Load Environment Variables

Load the variables into your current shell:

```

source .env

```

Verify that AWS authentication works:

```

aws sts get-caller-identity

```

If the command succeeds, the AWS CLI has authenticated successfully using the active credential configuration.

- **Best practice:** Prefer IAM roles, IAM Identity Center, or another short-lived credential mechanism over long-lived IAM user access keys whenever possible.

### Step 4: Initialize Terraform

Initialize the Terraform working directory:

```
cd aws-kubernetes-cluster
terraform init

```

This downloads the required providers and initializes the configured backend.

### Step 5: Validate the Configuration

Check the Terraform configuration for errors:

```

terraform fmt -recursive
terraform validate

```

Review the changes before provisioning resources:

```

terraform plan

```

### Step 6: Deploy the Infrastructure

Apply the Terraform configuration:

```

terraform apply

```

Review the execution plan and type yes when Terraform requests confirmation.

Terraform will provision the AWS resources declared in the configuration.

Depending on the implementation, these resources may include:

- VPC and subnets.
- Internet gateway and route tables.
- EC2 instances.
- Security groups.
- Instance profiles and IAM policies.
- Bootstrap scripts or configuration resources.

The exact resources depend on the Terraform files in the repository.

## Security Architecture

Security is an important part of this project.

### Bastion Host

The Bastion Host serves as a controlled entry point for administrative access to private infrastructure.

Recommended practices:

- Allow SSH access only from trusted IP addresses.
- Avoid exposing SSH to the entire internet (0.0.0.0/0).
- Use SSH keys or another secure authentication mechanism.
- Avoid storing private keys inside the repository.
- Restrict access to the proxy service.

### Private Kubernetes Nodes

The master and worker nodes are designed to operate without direct public internet access.

Recommended practices:

- Do not assign public IP addresses to private nodes.
- Restrict inbound traffic through security groups.
- Allow required Kubernetes communication only between trusted nodes and administrative endpoints.
- Configure outbound access through the intended proxy.
- Avoid exposing the Kubernetes API server publicly unless there is a specific, secured requirement.

### Join Worker Nodes

After the control plane is initialized, generate a worker join command on the master:

```

sudo kubeadm token create --print-join-command

```

Run the resulting command on each worker node with sudo and --node-name=worker1 / worker2.

The generated command includes cluster-specific connection and authentication information. Do not publish a live join token in the repository.

