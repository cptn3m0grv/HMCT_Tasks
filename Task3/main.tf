provider "aws" {
    access_key = "**"
    secret_key = "**"
    token = "**"
    region = "**"
}

resource "aws_vpc" "grv-t3-vpc" {
    cidr_block = "192.168.0.0/16"
    enable_dns_support =  true
    enable_dns_hostnames = true
    tags = {
        Environment = "Production"
        Name = "grv-t3-vpc"
    }
}

resource "aws_subnet" "grv-t3-public" {
    depends_on = [ aws_vpc.grv-t3-vpc ]
    vpc_id = "${aws_vpc.grv-t3-vpc.id}"
    cidr_block = "192.168.0.0/24"
    map_public_ip_on_launch = "true"
    availability_zone = "us-east-1a"
    tags = {
        Environment = "Production"
        Name= "grv-t3-public-subnet"
    }
}

resource "aws_subnet" "grv-t3-private" {
    depends_on = [ aws_vpc.grv-t3-vpc ]
    vpc_id = "${aws_vpc.grv-t3-vpc.id}"
    cidr_block = "192.168.1.0/24"
    availability_zone = "us-east-1b"
    tags = {
        Environment = "Production"
        Name = "grv-t3-private-subnet"
    }
}

resource "aws_internet_gateway" "grv-t3-ig" {
    depends_on = [ aws_vpc.grv-t3-vpc ]
    vpc_id = "${aws_vpc.grv-t3-vpc.id}"
    tags = {
        Environment = "Production"
        Name = "grv-t3-ig"
    }
}

resource "aws_route_table" "grv-t3-rt" {
    depends_on = [ aws_vpc.grv-t3-vpc ]
    vpc_id = "${aws_vpc.grv-t3-vpc.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.grv-t3-ig.id}"
    }
    tags = {
        Environment = "Production"
        Name = "grv-t3-rt"
    }
}

resource "aws_route_table_association" "grv-t3-public-subnet" {
    depends_on = [ aws_route_table.grv-t3-rt ]
    subnet_id      = "${aws_subnet.grv-t3-public.id}"
    route_table_id = "${aws_route_table.grv-t3-rt.id}"
}

resource "aws_security_group" "sg_wordpress" {
    depends_on = [ aws_vpc.grv-t3-vpc ]
    name = "sg_wordpress"
    description = "ssh, http allowed from anywhere."
    vpc_id = "${aws_vpc.grv-t3-vpc.id}"
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 80
        to_port = 80
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
        Name = "grv-t3-sg-wordpress"
    }
}

resource "aws_security_group" "sg_mysql" {
    depends_on = [ aws_vpc.grv-t3-vpc ]
    name = "sg_mysql"
    description = "sql only allowed"
    vpc_id = "${aws_vpc.grv-t3-vpc.id}"
    ingress{
        from_port = 22
        to_port = 22
        protocol = "tcp"
        security_groups = [ "${aws_security_group.sg_wordpress.id}" ]
    }
    ingress {
        from_port = 3306
        to_port = 3306
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
        Name = "grv-t3-sg-mysql"
    }
}

resource "aws_instance" "wordpress_instance" {
    depends_on = [ aws_security_group.sg_wordpress ]
    ami = "ami-098f16afa9edf40be"
    instance_type = "t2.micro"
    subnet_id = "${aws_subnet.grv-t3-public.id}"
    vpc_security_group_ids = [ "${aws_security_group.sg_wordpress.id}" ]
    key_name = "grv-t3-key"
    tags = {
        Environment = "Production"
        Name = "wordpress_instance"
    }
}

resource "aws_instance" "mysql_instance" {
    depends_on = [ aws_security_group.sg_mysql ]
    ami = "ami-098f16afa9edf40be"
    instance_type = "t2.micro"
    subnet_id = "${aws_subnet.grv-t3-private.id}"
    vpc_security_group_ids = [ "${aws_security_group.sg_mysql.id}" ]
    key_name = "grv-t3-key"
    tags = {
        Environment = "Production"
        Name = "mysql_instance"
    }
}

resource "null_resource" "wordpress_setup" {
	depends_on = [ aws_instance.wordpress_instance ] 

	connection {
		type = "ssh"
		user = "ec2-user"
		private_key = file("path/to/private/key/in/your/pc")
		host = aws_instance.wordpress_instance.public_ip
	}

	provisioner "remote-exec" {
		inline = [
			"sudo yum -y install php-mysqlnd php-fpm httpd tar curl php-json",
			"sudo systemctl start httpd",
			"sudo systemctl enable httpd",
			"sudo curl https://wordpress.org/latest.tar.gz --output /root/wordpress.tar.gz",
            "sudo tar xf /root/wordpress.tar.gz",
            "sudo cp -rf /home/ec2-user/wordpress/* /var/www/html/"
		]
	}
}