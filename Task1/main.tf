provider "aws" {
    access_key = "**"
    secret_key = "**"
    token = "**"
    region = "**"
}


resource "aws_security_group" "http_ssh" {
	name = "http_ssh"
	description = "Allowing HTTP and SSH"
	
	ingress {
		description = "HTTP_ENABLE"
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	ingress {
		description = "SSH_ENABLE"
		from_port = 22
		to_port = 22
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
		Name = "http_ssh"
	}
}

resource "tls_private_key" "tfkeypair" {
	algorithm = "RSA"
}

resource "aws_key_pair" "key_gen" {
	key_name = "tfkeypair"
	public_key = "${tls_private_key.tfkeypair.public_key_openssh}"
	
	depends_on = [ tls_private_key.tfkeypair ]	
}

resource "local_file" "key-file" {
	content = "${tls_private_key.tfkeypair.private_key_pem}"
	filename = "tfkeypair.pem"

	depends_on = [ tls_private_key.tfkeypair ]
}

resource "aws_instance" "web" {
	depends_on = [ local_file.key-file ]

	ami = "ami-09d95fab7fff3776c"
	instance_type = "t2.micro"
	key_name = "tfkeypair"
	security_groups = [ "http_ssh" ]
	
	tags = {
		Name = "WebServer"
	}
}

output "webserver_ip" {
	value = aws_instance.web.public_ip
}

resource "null_resource" "setup_instance" {
	depends_on = [ aws_instance.web ]
	
	connection {
		type = "ssh"
		user = "ec2-user"
		private_key =  file("path/to/private/key/in/your/pc")
		host = aws_instance.web.public_ip
	}

	provisioner "remote-exec" {
		inline = [
			"sudo yum install git httpd php -y",
			"sudo systemctl restart httpd",
			"sudo systemctl enable httpd"
		]
	}
}


resource "aws_ebs_volume" "ebs1" {
	depends_on = [ null_resource.setup_instance ]
	
	availability_zone = aws_instance.web.availability_zone
	size = 1
	tags = {
		Name = "lwebs"
	}
}

resource "aws_volume_attachment" "ebs_att" {
	depends_on = [ aws_ebs_volume.ebs1 ]
	
	device_name = "/dev/sdh"
	volume_id = "${aws_ebs_volume.ebs1.id}"
	instance_id = "${aws_instance.web.id}"
	force_detach = true
}

resource "null_resource" "code_setup" {
	depends_on = [ aws_volume_attachment.ebs_att ] 

	connection {
		type = "ssh"
		user = "ec2-user"
		private_key =  file("path/to/private/key/in/your/pc")
		host = aws_instance.web.public_ip
	}

	provisioner "remote-exec" {
		inline = [
			"sudo mkfs.ext4 /dev/xvdh",
			"sudo mount /dev/xvdh /var/www/html",
			"sudo rm -rf /var/www/html/*",
			"sudo git clone https://github.com/cptn3m0grv/multicloud.git /var/www/html/"
		]
	}
}