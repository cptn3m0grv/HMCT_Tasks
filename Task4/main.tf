provider "aws" {
    access_key = "**"
    secret_key = "**"
    token = "**"
    region = "**"
}

resource "aws_vpc" "grv-t4-vpc" {
    cidr_block = "192.168.0.0/16"
    enable_dns_support =  true
    enable_dns_hostnames = true
    tags = {
        Environment = "Production"
        Name = "grv-t4-vpc"
    }
}

resource "aws_subnet" "grv-t4-public" {
    depends_on = [ aws_vpc.grv-t4-vpc ]
    vpc_id = "${aws_vpc.grv-t4-vpc.id}"
    cidr_block = "192.168.0.0/24"
    map_public_ip_on_launch = "true"
    availability_zone = "us-east-1a"
    tags = {
        Environment = "Production"
        Name= "grv-t4-public-subnet"
    }
}

resource "aws_subnet" "grv-t4-private" {
    depends_on = [ aws_vpc.grv-t4-vpc ]
    vpc_id = "${aws_vpc.grv-t4-vpc.id}"
    cidr_block = "192.168.1.0/24"
    availability_zone = "us-east-1b"
    tags = {
        Environment = "Production"
        Name = "grv-t4-private-subnet"
    }
}

resource "aws_internet_gateway" "grv-t4-ig" {
    depends_on = [ aws_vpc.grv-t4-vpc ]
    vpc_id = "${aws_vpc.grv-t4-vpc.id}"
    tags = {
        Environment = "Production"
        Name = "grv-t4-ig"
    }
}

resource "aws_route_table" "grv-t4-rt" {
    depends_on = [ aws_vpc.grv-t4-vpc ]
    vpc_id = "${aws_vpc.grv-t4-vpc.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.grv-t4-ig.id}"
    }
    tags = {
        Environment = "Production"
        Name = "grv-t4-rt"
    }
}

resource "aws_route_table_association" "grv-t4-public-subnet" {
    depends_on = [ aws_route_table.grv-t4-rt ]
    subnet_id      = "${aws_subnet.grv-t4-public.id}"
    route_table_id = "${aws_route_table.grv-t4-rt.id}"
}

resource "aws_eip" "eip-t4" {
    depends_on = [ aws_route_table_association.grv-t4-public-subnet ]
    vpc = true
}

resource "aws_nat_gateway" "grv-t4-ng" {
    depends_on = [aws_eip.eip-t4]
    allocation_id = aws_eip.eip-t4.id
    subnet_id = aws_subnet.grv-t4-public.id
    tags = {
        Name = "grv-t4-ng"
    }
}

resource "aws_route_table" "grv-t4-ng-rt" {
    depends_on = [ aws_nat_gateway.grv-t4-ng ]
    vpc_id = "${aws_vpc.grv-t4-vpc.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_nat_gateway.grv-t4-ng.id }"
    }
}

resource "aws_route_table_association" "grv-t4-rt2" {
    depends_on = [ aws_route_table.grv-t4-ng-rt ]
    subnet_id = "${aws_subnet.grv-t4-private.id}"
    route_table_id = "${aws_route_table.grv-t4-ng-rt.id}"
}

resource "aws_security_group" "sg_wordpress" {
    depends_on = [ aws_vpc.grv-t4-vpc ]
    name = "sg_wordpress"
    description = "allow all"
    vpc_id = "${aws_vpc.grv-t4-vpc.id}"
    ingress {
        from_port = 0
        to_port = 65535
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Environment = "Production"
        Name = "grv-t4-sg-wordpress"
    }
}

resource "aws_security_group" "sg_mysql" {
    depends_on = [ aws_vpc.grv-t4-vpc ]
    name = "sg_mysql"
    description = "allow only for wp instance"
    vpc_id = "${aws_vpc.grv-t4-vpc.id}"
    ingress {
        from_port = 0
        to_port = 65535
        protocol = "tcp"
        security_groups = [ "${aws_security_group.sg_wordpress.id}" ] 
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Environment = "Production"
        Name = "grv-t4-sg-mysql"
    }
}

resource "aws_instance" "wordpress_instance" {
    depends_on = [ aws_security_group.sg_wordpress ]
    ami = "ami-098f16afa9edf40be"
    instance_type = "t2.micro"
    subnet_id = "${aws_subnet.grv-t4-public.id}"
    vpc_security_group_ids = [ "${aws_security_group.sg_wordpress.id}" ]
    key_name = "grv-t4-key"
    tags = {
        Environment = "Production"
        Name = "wordpress_instance"
    }
}

resource "aws_instance" "mysql_instance" {
    depends_on = [ aws_security_group.sg_mysql ]
    ami = "ami-098f16afa9edf40be"
    instance_type = "t2.micro"
    subnet_id = "${aws_subnet.grv-t4-private.id}"
    vpc_security_group_ids = [ "${aws_security_group.sg_mysql.id}" ]
    key_name = "grv-t4-key"
    tags = {
        Environment = "Production"
        Name = "mysql_instance"
    }
}

resource "null_resource" "wordpress_setup" {
    depends_on = [ aws_instance.wordpress_instance, aws_instance.mysql_instance ]

	connection {
		type = "ssh"
		user = "ec2-user"
		private_key =  file("path/to/private/key/in/your/pc")
		host = aws_instance.wordpress_instance.public_ip
	}

	provisioner "remote-exec" {
		inline = [
            "sudo dnf -y install git",
            "git clone https://github.com/cptn3m0grv/multicloud.git",
			"sudo tee -a /etc/yum.repos.d/docker.repo <<EOF",
            "[docker]",
            "baseurl=https://download.docker.com/linux/centos/7/x86_64/stable",
            "gpgcheck=0",
            "EOF",
            "sudo dnf -y install docker-ce --nobest",
            "sudo systemctl start docker",
            "sudo systemctl enable docker",
            "sudo docker pull wordpress:5.1.1-php7.3-apache",
            "sudo docker run -dit -p 80:80 --name webserver wordpress:5.1.1-php7.3-apache",
			"tee -a /home/ec2-user/script.sh <<EOF",
			"sudo tee -a /etc/yum.repos.d/docker.repo <<EOH",
			"[docker]",
            "baseurl=https://download.docker.com/linux/centos/7/x86_64/stable",
            "gpgcheck=0",
            "EOH",
            "sudo dnf -y install docker-ce --nobest",
            "sudo systemctl start docker",
            "sudo systemctl enable docker",
            "sudo docker pull mysql:5.7",
            "sudo docker run -dit -e MYSQL_ROOT_PASSWORD=rootpass -e MYSQL_USER=gaurav -e MYSQL_PASSWORD=gauravpass -e MYSQL_DATABASE=myWordpressDB -p 3306:3306 --name database mysql:5.7",
            "EOF",
            "sudo chmod 400 multicloud/grv-t4-key.pem",
            "sudo chmod +x script.sh",
            "ssh  -o StrictHostKeyChecking=no  ec2-user@${aws_instance.mysql_instance.private_ip} -i multicloud/grv-t4-key.pem 'bash -s' < ./script.sh"
		]
	}
}

resource "null_resource" "wordress_access" {
    depends_on = [ null_resource.wordpress_setup ]
	
	provisioner "local-exec" {
		command = "msedge ${aws_instance.wordpress_instance.public_ip}"
	}
}

output "sql_host_addr" {
    depends_on = [ null_resource.wordress_access ]
    value = "Use this IP as the MYSQL HOST  ---------> ${aws_instance.mysql_instance.private_ip} <---------"
}