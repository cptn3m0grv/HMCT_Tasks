provider "aws" {    
    access_key = "**"
    secret_key = "**"
    token = "**"
	region = "us-east-1"
}

resource "aws_db_subnet_group" "default" {
	    name = "main"
	    subnet_ids = ["*","*","*"]
	    tags = {
	      Name = "my subnets"
	    }
	  
}

resource "aws_db_instance" "grv-t6-db" {
    engine = "mysql"
    engine_version = "5.7.30"
    instance_class = "db.t2.micro"
    allocated_storage = 10
    storage_type = "gp2"
    name = "wpdb"
    username = "gaurav"
    password = "redhat"
    port = "3306"
    publicly_accessible = true
    skip_final_snapshot = true
    parameter_group_name = "default.mysql5.7"
    db_subnet_group_name = "${aws_db_subnet_group.default.name}"
    tags = {
      Name = "prodDB"
    }
}
	

