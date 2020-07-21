provider "aws" {
    access_key = "**"
    secret_key = "**"
    token = "**"
    region = "**"
}


resource "aws_security_group" "sg_efs" {
  name = "sg_efs"
  description = "Allowing NFS for the EFS"
  ingress {
    from_port = 2049
    to_port = 2049
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
    Name = "sg_efs"
  }
}

resource "aws_security_group" "grv-t2-sg" {
  name = "grv-t2-sg"
  description = "Allowing HTTP SSH NFS"
  ingress {
      from_port = 80
	  to_port = 80
	  protocol = "tcp"
	  cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
	  from_port = 22
	  to_port = 22
	  protocol = "tcp"
	  cidr_blocks = ["0.0.0.0/0"]
  }	
  ingress{
	  from_port = 443
	  to_port = 443
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
	  Name = "grv-t2-sg"
  }
}

resource "aws_instance" "webserver" {
  depends_on = [ aws_security_group.grv-t2-sg ]
  ami = "ami-098f16afa9edf40be"
  instance_type = "t2.micro"
  key_name = "grv-t2-key"
  security_groups = [ "grv-t2-sg" ]	
  tags = {
    Environment = "Production"	
	  Name = "WebServer"
  }
}

resource "aws_efs_file_system" "allow_nfs" {
  depends_on = [ aws_security_group.sg_efs]
  creation_token = "allow_nfs"
  tags = {
    Name = "allow_nfs"
  }
}

resource "aws_efs_mount_target" "mount_target" {
  depends_on = [ aws_efs_file_system.allow_nfs ]
  file_system_id = "${aws_efs_file_system.allow_nfs.id}"
  subnet_id = "${aws_instance.webserver.subnet_id}"
  security_groups = ["${aws_security_group.sg_efs.id}" ] 
}


resource "null_resource" "instance_setup" {
	depends_on = [ aws_instance.webserver, aws_efs_mount_target.mount_target ]
	
	connection {
		type = "ssh"
		user = "ec2-user"
		private_key = file("path/to/private/key/in/your/pc")
		host = aws_instance.webserver.public_ip
	}

	provisioner "remote-exec" {
		inline = [
			"sudo yum install git httpd php nfs-utils -y",
			"sudo systemctl start httpd",
			"sudo systemctl enable httpd",
            "sudo mount ${aws_efs_file_system.allow_nfs.dns_name}:/ /var/www/html/",
            "sudo git clone https://github.com/cptn3m0grv/HMCT_T2.git /var/www/html/",
		]
	}
}
resource "aws_s3_bucket" "t2-bucket" {
  depends_on = [ null_resource.instance_setup ]
	bucket = "grv-t2-bucket"
	acl = "public-read"
	force_destroy = true
	tags = {
		Name = "Bucky"
		Environment = "Dev"
	}
}

resource "aws_s3_bucket_object" "image" {
	depends_on = [ aws_s3_bucket.t2-bucket ]
	acl = "public-read"
	bucket = "${aws_s3_bucket.t2-bucket.bucket}"
	key = "image.jpg"
	source = "image.jpg"
	content_type = "image/jpg"
	force_destroy = true
}

resource "aws_cloudfront_distribution" "distro" {
	depends_on = [ aws_s3_bucket.t2-bucket ]
    origin {
 		domain_name = aws_s3_bucket.t2-bucket.bucket_regional_domain_name
		origin_id = "aws_s3_bucket.t2-bucket.bucket.s3_origin_id"
		custom_origin_config {
			http_port = 80
			https_port = 80
			origin_protocol_policy = "match-viewer"
			origin_ssl_protocols = ["TLSv1","TLSv1.1","TLSv1.2"]
		}
	}
	enabled = true
	is_ipv6_enabled = true	
	default_cache_behavior {
		allowed_methods = ["DELETE","HEAD","GET","OPTIONS","PATCH","POST","PUT"]
		cached_methods = ["HEAD","GET"]
		target_origin_id = "aws_s3_bucket.t2-bucket.bucket.s3_origin_id"
		forwarded_values {
			query_string = false
			cookies {
				forward = "none"
			}
		}
		viewer_protocol_policy = "allow-all"
	 	min_ttl = 0
		default_ttl = 3600
		max_ttl = 86400
	}
	restrictions {
		geo_restriction {
			restriction_type = "none"
		}
	}
	tags = {
		Environment = "cdn"
	}
	viewer_certificate {
		cloudfront_default_certificate = true
	}
}

resource "null_resource" "null_remote" {
  depends_on = [ aws_cloudfront_distribution.distro ]
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = file("path/to/private/key/in/your/pc")
    host = "${aws_instance.webserver.public_ip}"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"<img src='${aws_cloudfront_distribution.distro.domain_name}/${aws_s3_bucket_object.image.key}' />\" >> /var/www/html/index.html",
      "EOF"
    ]
  }
}

resource "null_resource" "null_local" {
	depends_on = [ null_resource.null_remote ]
	provisioner "local-exec" {
		command = "msedge ${aws_instance.webserver.public_ip}"
	}
}