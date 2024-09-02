resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "pem_file" {
  filename        = pathexpand("~/.ssh/eks-aws.pem")
  file_permission = "600"
  content         = tls_private_key.key_pair.private_key_pem
}

resource "aws_key_pair" "eks_kp" {
  key_name   = "eks_kp"
  public_key = trimspace(tls_private_key.key_pair.public_key_openssh)
}

data "aws_iam_policy_document" "assume_role_ec2" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node_instance_role" {
  name               = var.node_role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  ]
  path = "/"
}

resource "aws_iam_instance_profile" "node_instance_profile" {
  name = "NodeInstanceProfile"
  path = "/"
  role = aws_iam_role.node_instance_role.id
}

resource "aws_security_group" "node_security_group" {
  name        = "NodeSecurityGroupIngress"
  description = "Security group for all nodes in the cluster"
  vpc_id      = data.aws_vpc.default_vpc.id
  tags = {
    "Name" = "NodeSecurityGroupIngress"
  }
}

resource "aws_vpc_security_group_ingress_rule" "node_security_group_ingress" {
  description                  = "Allow node to communicate with each other"
  ip_protocol                  = "-1"
  security_group_id            = aws_security_group.node_security_group.id
  referenced_security_group_id = aws_security_group.node_security_group.id
}

resource "aws_vpc_security_group_egress_rule" "node_egress_all" {
  description       = "Allow node egress to anywhere"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  security_group_id = aws_security_group.node_security_group.id
}

resource "aws_vpc_security_group_ingress_rule" "node_security_group_from_control_plane_ingress" {
  description                  = "Allow Kubelet and pods to receive communication from the cluster control plane"
  security_group_id            = aws_security_group.node_security_group.id
  referenced_security_group_id = data.aws_eks_cluster.demo_eks.vpc_config[0].cluster_security_group_id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "TCP"
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_egress_to_node_security_group_on_443" {
  description                  = "Pods running API servers on port 443 to receive communication from cluster control plane"
  security_group_id            = aws_security_group.node_security_group.id
  referenced_security_group_id = data.aws_eks_cluster.demo_eks.vpc_config[0].cluster_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "TCP"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_control_plane_security_group_ingress" {
  description                  = "Pods to communicate with the cluster API Server"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "TCP"
  referenced_security_group_id = aws_security_group.node_security_group.id
  security_group_id            = data.aws_eks_cluster.demo_eks.vpc_config[0].cluster_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "control_plane_egress_to_node_security_group" {
  description                  = "Cluster control plane to communicate with worker Kubelet and pods"
  referenced_security_group_id = aws_security_group.node_security_group.id
  security_group_id            = data.aws_eks_cluster.demo_eks.vpc_config[0].cluster_security_group_id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "TCP"
}

resource "aws_vpc_security_group_egress_rule" "control_plane_egress_to_node_security_group_on_443" {
  description                  = "Cluster control plane to communicate with pods running extension API servers on port 443"
  referenced_security_group_id = aws_security_group.node_security_group.id
  security_group_id            = data.aws_eks_cluster.demo_eks.vpc_config[0].cluster_security_group_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "TCP"
}

resource "aws_launch_template" "node_launch_template" {
  name = "NodeLaunchTemplate"
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      delete_on_termination = true
      volume_size           = 30
      volume_type           = "gp2"
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.node_instance_profile.name
  }

  key_name      = aws_key_pair.eks_kp.key_name
  instance_type = "t3.medium"
  vpc_security_group_ids = [
    aws_security_group.node_security_group.id
  ]

  tags = {
    "Name" = "NodeLaunchTemplate"
  }

  image_id = data.aws_ssm_parameter.node_ami.value

  metadata_options {
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "worker-node"
    }
  }

  user_data = base64encode(<<EOF
    #!/bin/bash
    set -o xtrace
    /etc/eks/bootstrap.sh ${var.cluster_name}
    /opt/aws/bin/cfn-signal --exit-code $? \
                --stack  ${var.cluster_name}-stack \
                --resource NodeGroup  \
                --region us-east-1
    EOF
  )
}


resource "time_sleep" "wait_30_seconds" {
  depends_on = [
    aws_launch_template.node_launch_template
    ]

  create_duration = "30s"
}

resource "aws_cloudformation_stack" "autoscaling_group" {
  depends_on = [
    time_sleep.wait_30_seconds
  ]
  name = "eks-cluster-stack"
  template_body = <<EOF
Description: "Node autoscaler"
Resources:
  NodeGroup:
    Type: AWS::AutoScaling::AutoScalingGroup
    Properties:
      VPCZoneIdentifier: ["${data.aws_subnets.public.ids[0]}","${data.aws_subnets.public.ids[1]}", "${data.aws_subnets.public.ids[2]}"]
      MinSize: "${var.node_group_min_size}"
      MaxSize: "${var.node_group_max_size}"
      DesiredCapacity: "${var.node_group_desired_capacity}"
      HealthCheckType: EC2
      LaunchTemplate:
        LaunchTemplateId: "${aws_launch_template.node_launch_template.id}"
        Version: "${aws_launch_template.node_launch_template.latest_version}"
    UpdatePolicy:
    # Ignore differences in group size properties caused by scheduled actions
      AutoScalingScheduledAction:
        IgnoreUnmodifiedGroupSizeProperties: true
      AutoScalingRollingUpdate:
        MaxBatchSize: 1
        MinInstancesInService: "${var.node_group_desired_capacity}"
        PauseTime: PT5M
Outputs:
  NodeAutoScalingGroup:
    Description: The autoscaling group
    Value: !Ref NodeGroup
  EOF
}
