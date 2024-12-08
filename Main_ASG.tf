#Security group Load Balancer
resource "aws_security_group" "SG01-LB01" {
  name        = "SG01-LB01"
  description = "LB_security_group"
  vpc_id      = aws_vpc.VPC-London-prod.id

  ingress {
    description = "MyHomePage"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "SG01-LB01"
    Service = "J-tele-doctor"

  }
}

#Security group Target Group
resource "aws_security_group" "SG01-TG01" {
  name        = "SG01-TG01"
  description = "TG_security_group"
  vpc_id      = aws_vpc.VPC-London-prod.id

  ingress {
    description = "MyHomePage"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "SG01-TG01"
    Service = "J-tele-doctor"

  }
}

#Launch template
resource "aws_launch_template" "LT01-London-prod" {
  name_prefix   = "LT01-London-prod"
  image_id      = "ami-0c76bd4bd302b30ec"  
  instance_type = "t2.micro"

  key_name = "basiclinux"

  vpc_security_group_ids = [aws_security_group.SG01-TG01.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd

    # Get the IMDSv2 token
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

    # Background the curl requests
    curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4 &> /tmp/local_ipv4 &
    curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone &> /tmp/az &
    curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/ &> /tmp/macid &
    wait

    macid=$(cat /tmp/macid)
    local_ipv4=$(cat /tmp/local_ipv4)
    az=$(cat /tmp/az)
    vpc=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$macid/vpc-id)

    # Create HTML file
    cat <<-HTML > /var/www/html/index.html
    <!doctype html>
    <html lang="en" class="h-100">
    <head>
    <title>Details for EC2 instance</title>
    </head>
    <body>
    <div>
    <h1>J-Tele-Doctor</h1>
    <h1>London</h1>
    <p><b>Instance Name:</b> $(hostname -f) </p>
    <p><b>Instance Private Ip Address: </b> $local_ipv4</p>
    <p><b>Availability Zone: </b> $az</p>
    <p><b>Virtual Private Cloud (VPC):</b> $vpc</p>
    </div>
    </body>
    </html>
    HTML
" > /var/www/html/index.html

# Clean up the temp files
rm -f /tmp/local_ipv4 /tmp/az /tmp/macid

# Install rsyslog
yum install -y rsyslog

# Start and enable rsyslog
systemctl start rsyslog
systemctl enable rsyslog

# Configure rsyslog to forward logs to the syslog server
echo "
*.* @@SYSLOG-SERVER-IP:514
" >> /etc/rsyslog.conf

# Restart rsyslog to apply changes
systemctl restart rsyslog

  EOF
  )
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = "LT01-London-prod"
      Service = "J-tele-Doctor"
      
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

#Target group
resource "aws_lb_target_group" "TG01-London-prod" {
  name     = "TG01-London-prod"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.VPC-London-prod.id
  target_type = "instance"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200"
  }

  tags = {
    Name    = "TG01-London-prod"
    Service = "J-Tele-Doctor"
  }
}

#Load Balancer
resource "aws_lb" "LB01-London-prod" {
  name               = "LB01-London-prod"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.SG01-LB01.id]
  subnets            = [
    aws_subnet.Subnet-A-London-prod-Public.id,
    aws_subnet.Subnet-B-London-prod-Public.id
  ]
  enable_deletion_protection = false
#Lots of death and suffering here, make sure it's false. Prevents terraform from deleting the load balancer, prevents accidental deletions

  tags = {
    Name    = "LB01-London-prod"
    Service = "J-tele-Doctor"
  }
}


#Scaling Group
resource "aws_autoscaling_group" "ASG01-London-prod" {
  name_prefix           = "ASG01-London-prod"
  min_size              = 2
  max_size              = 4
  desired_capacity      = 3
  vpc_zone_identifier   = [
    aws_subnet.Subnet-A-London-prod-Private.id,
    aws_subnet.Subnet-B-London-prod-Private.id
  ]
  health_check_type          = "ELB"
  health_check_grace_period  = 300
  force_delete               = true
  target_group_arns          = [aws_lb_target_group.TG01-London-prod.arn]

  launch_template {
    id      = aws_launch_template.LT01-London-prod.id
    version = "$Latest"
  }

  enabled_metrics = ["GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances", "GroupTotalInstances"]

  # Instance protection for launching
  initial_lifecycle_hook {
    name                  = "instance-protection-launch"
    lifecycle_transition  = "autoscaling:EC2_INSTANCE_LAUNCHING"
    default_result        = "CONTINUE"
    heartbeat_timeout     = 60
    notification_metadata = "{\"key\":\"value\"}"
  }

  # Instance protection for terminating
  initial_lifecycle_hook {
    name                  = "scale-in-protection"
    lifecycle_transition  = "autoscaling:EC2_INSTANCE_TERMINATING"
    default_result        = "CONTINUE"
    heartbeat_timeout     = 300
  }

  tag {
    key                 = "Name"
    value               = "ASG01-London-prod"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "Production"
    propagate_at_launch = true
  }
}


# Auto Scaling Policy
resource "aws_autoscaling_policy" "ASG01_London_prod_Scaling_policy" {
  name                   = "ASG01_London_prod_Scaling_policy"
  autoscaling_group_name = aws_autoscaling_group.ASG01-London-prod.name

  policy_type = "TargetTrackingScaling"
  estimated_instance_warmup = 120

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 75.0
  }
}
