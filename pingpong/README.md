# PingPong Repository for SatSure

In this repository you will find

* Code for ping-pong api exposed with path '/ping' that returns a response 'Pong...'
* Dockerfile to create a docker image of the ping-pong api and push it to Container Registry of your choice
* eks-cluster directory, comprised of Terraform code to create a EKS Cluster on AWS
* k8s-manifests directory, comprised of Deployment and Service for ping-pong application
* Steps to pull prometheus metrics from EKS Cluster and visualizing those on Grafana dashboard
* Screenshots from each steps performed are stored in screenshots folder

# Getting started/ Useful Information

* This deployment requires an AWS Account
* All steps should be followed in order to deploy an end-to-end implementation of ping-pong api
* AWS CloudShell is used to connect to AWS EKS Cluster

# Creating Docker Image for ping-pong api

* Change directory to 'api/ping', where ping-pong code along with prometheus instrumentation code resides in main.py file
* Dockerfile is also present to create docker image of the ping-pong api. Perform below step to create a docker image and push it to docker hub

```buildoutcfg
docker build -t <docker-repository-name>/<image-name>:<tag-name> .
docker push <docker-repository-name>/<image-name>:<tag-name>
```

For this task - We will make use of nikhilsaxena/ping:v1 docker image

* Connect to AWS CloudShell and take a clone of this Git repo - https://github.com/nikhilsaxena/pingpong.git

```buildoutcfg
git clone https://github.com/nikhilsaxena/pingpong.git
```

# Creating EKS Cluster

* Once you have cloned the Git Repo, perform below steps to create an AWS EKS Cluster
* Install Terraform on Amazon Linux V2 (AWS CloudShell)
```buildoutcfg
sudo yum update -y
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum install -y terraform
```
* Change directory to 'eks-cluster' and perform below steps
```buildoutcfg
terraform init
terraform workspace new master
terraform plan -out terraform.out
terraform apply terraform.out
```
* Creation of eks cluster will take around 15-20 mins.
* Meanwhile update the kubeconfig file on CloudShell using below command
```buildoutcfg
aws eks update-kubeconfig --name demo-eks --region us-east-1
```

# Deploying ping-pong api on EKS Cluster

* Change Directory to k8s-manifests, Copy the 'NodeInstanceRole' from terraform outputs and paste it in aws-auth-cm.yaml file, line 8 and perform below steps
```buildoutcfg
kubectl apply -f k8s-manifests/aws-auth-cm.yaml
kubectl get nodes -o wide --watch
```
Observe the kubectl get nodes command, until Nodes Status turns to 'Ready'

* For deploying your ping-pong api and exposing it through LoadBalancer Service, perform below step
```buildoutcfg
kubectl apply -f ping-app.yaml
kubectl get pods,svc
```
* You can get the endpoint of ping-service and make a curl request to check, if the app is deployed as expected or not
```buildoutcfg
curl <long dns-name for ping-service>:5000/ping
```
* If everything is deployed correctly, you will see "Pong..." response
* Prometheus metrics can also be fetched from the same endpoint using below curl command
```buildoutcfg
curl <long dns-name for ping-service>:5000/metrics
```

# Installing Helm for Prometheus and Grafana

* Perform below steps to install helm
```buildoutcfg
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

* Once helm is installed, you can make use of kube-prometheus-stack helm chart to use Prometheus and Grafana
* Use below steps to pull the helm chart

```buildoutcfg
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm pull prometheus-community/kube-prometheus-stack --untar
```

* --untar: As we have to configure Prometheus to scrape all the metrics that we have exposed in our ping-pong api
* You will find a directory with name 'kube-prometheus-stack'
* Locate the values.yaml file and make below changes
* Search for additionalScrapeConfigs json object and add below lines
```buildoutcfg
additionalScrapeConfigs:
  - job_name: 'ping-service'
    static-configs:
       - targets: ['<long dns-name for ping-service>:5000']
    scrape_interval: 10s
```

* Search for 'grafana:' keyword and change it Service Type to LoadBalancer
* Perform below steps to install the helm chart
```buildoutcfg
helm install monitoring ./kube-prometheus-stack
```
* Fetch the grafana service endpoint and open in new tab
* Furnish Credentials as admin:prom-operator

# Visualizing the Grafana Dashboard

## For ping-pong Service
* Create a new Dashboard
* Select Data Source as Prometheus and metrics as ping_requests_total

## For Node and Pod Network Statistics
* Select Source as AlertManager
* Use metrics as NodeExporter/Nodes or Networking/Pod

All screenshots of above steps can be found inside screenshot folder.