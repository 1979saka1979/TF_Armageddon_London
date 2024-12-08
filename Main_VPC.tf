#VPC
resource "aws_vpc" "VPC-London-prod" {
    cidr_block = "10.152.0.0/16"
    tags = {
        Name: "VPC-London-prod"
        vpc_env = "prod"
        service = "J-tele-Doctor"
    }
}
#Subnets
resource "aws_subnet" "Subnet-A-London-prod-Public" {
    vpc_id = aws_vpc.VPC-London-prod.id
    cidr_block = "10.152.1.0/24"
    availability_zone = "eu-west-2a"
    map_public_ip_on_launch = true
    tags = {
        Name: "Subnet-A-London-prod-Public"
        service = "J-tele-Doctor"
    }
}
resource "aws_subnet" "Subnet-A-London-prod-Private" {
    vpc_id = aws_vpc.VPC-London-prod.id
    cidr_block = "10.152.11.0/24"
    availability_zone = "eu-west-2a"
    tags = {
        Name: "Subnet-A-London-prod-Private"
        service = "J-tele-Doctor"
    }
}

resource "aws_subnet" "Subnet-B-London-prod-Public" {
    vpc_id = aws_vpc.VPC-London-prod.id
    cidr_block = "10.152.2.0/24"
    availability_zone = "eu-west-2b"
    map_public_ip_on_launch = true
    tags = {
        Name: "Subnet-B-London-prod-Public"
        service = "J-tele-Doctor"
    }
}
resource "aws_subnet" "Subnet-B-London-prod-Private" {
    vpc_id = aws_vpc.VPC-London-prod.id
    cidr_block = "10.152.12.0/24"
    availability_zone = "eu-west-2b"
    tags = {
        Name: "Subnet-B-London-prod-Private"
        service = "J-tele-Doctor"
    }
}

#Internet Gateway
resource "aws_internet_gateway" "prod-igw" {
    vpc_id = aws_vpc.VPC-London-prod.id 
    tags = {
        Name = "prod_IGW"
        service = "J-tele-Doctor"
    }
}
#Elastic IP
resource "aws_eip" "eip_prod" {
  domain = "vpc"

  tags = {
    Name = "eip_prod"
  }
}
#Nat Gateway
resource "aws_nat_gateway" "nat_prod" {
  allocation_id = aws_eip.eip_prod.id
  subnet_id     = aws_subnet.Subnet-A-London-prod-Private.id

  tags = {
    Name = "nat_prod"
  }

  depends_on = [aws_internet_gateway.prod-igw]
}
#Route table
resource "aws_route_table" "Public_RTB" {
  vpc_id = aws_vpc.VPC-London-prod.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod-igw.id
  }
  
  tags = {
    Name = "Public_RTB"
    Service = "J-Tele-Doctor"
  }
}

resource "aws_route_table" "Private_RTB" {
  vpc_id = aws_vpc.VPC-London-prod.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_prod.id
  }
 
  
  tags = {
    Name = "Private_RTB"
    Service = "J-Tele-Doctor"
  }   
}
 
#Route Table Associations
resource "aws_route_table_association" "public-eu-west-2a" {
    subnet_id = aws_subnet.Subnet-A-London-prod-Public.id
    route_table_id = aws_route_table.Public_RTB.id 
  
}
resource "aws_route_table_association" "public-eu-west-2b" {
    subnet_id = aws_subnet.Subnet-B-London-prod-Public.id
    route_table_id = aws_route_table.Public_RTB.id 
  
}
resource "aws_route_table_association" "private-eu-west-2a" {
    subnet_id = aws_subnet.Subnet-A-London-prod-Private.id
    route_table_id = aws_route_table.Private_RTB.id 
  
}
resource "aws_route_table_association" "private-eu-west-2b" {
    subnet_id = aws_subnet.Subnet-B-London-prod-Private.id
    route_table_id = aws_route_table.Private_RTB.id 
  
}

