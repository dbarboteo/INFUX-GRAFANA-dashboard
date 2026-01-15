# Generar clave SSH automáticamente
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Crear key pair en AWS
resource "aws_key_pair" "terraform_key" {
  key_name   = "terraform-key-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Guardar la clave privada localmente
resource "local_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/terraform-key.pem"
  file_permission = "0400"
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Obtener la AMI más reciente de Ubuntu 24.04 LTS
data "aws_ami" "ubuntu_2404" {
  owners      = ["099720109477"] # Canonical
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Obtener información de la VPC por defecto
data "aws_vpc" "default" {
  default = true
}

# Obtener subnets de la VPC por defecto
data "aws_subnets" "default_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group para InfluxDB
resource "aws_security_group" "sg_influxdb" {
  name   = "sg_influxdb"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "InfluxDB from Grafana"
    from_port       = 8086
    to_port         = 8086
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_grafana.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group para Grafana
resource "aws_security_group" "sg_grafana" {
  name   = "sg_grafana"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana HTTP"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Elastic IP para Grafana (se crea primero, sin asignar)
resource "aws_eip" "grafana_eip" {
  domain = "vpc"

  tags = {
    Name = "PT-Grafana-EIP"
  }
}

# Instancia InfluxDB
resource "aws_instance" "ubuntu_influxdb" {
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = "t2.micro"
  subnet_id              = data.aws_subnets.default_subnets.ids[0]
  vpc_security_group_ids = [aws_security_group.sg_influxdb.id]
  key_name               = aws_key_pair.terraform_key.key_name

  user_data = templatefile("${path.module}/scripts/influxdb.sh", {
    mosquito_py      = filebase64("${path.module}/scripts/mosquito.py")
    requirements_txt = filebase64("${path.module}/scripts/requirements.txt")
  })

  tags = {
    Name = "PT-InfluxDB"
  }
}

# Instancia Grafana
resource "aws_instance" "ubuntu_grafana" {
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = "t2.micro"
  subnet_id              = data.aws_subnets.default_subnets.ids[0]
  vpc_security_group_ids = [aws_security_group.sg_grafana.id]
  key_name               = aws_key_pair.terraform_key.key_name

  user_data = templatefile("${path.module}/scripts/grafana.sh", {
    influxdb_private_ip = aws_instance.ubuntu_influxdb.private_ip
  })

  user_data_replace_on_change = true

  tags = {
    Name = "PT-Grafana"
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  # Provisioner para copiar el dashboard JSON
  provisioner "file" {
    source      = "${path.module}/scripts/dashboard-fixed.json"
    destination = "/tmp/dashboard.json"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = self.public_ip
    }
  }

  # Provisioner para copiar el script de carga
  provisioner "file" {
    source      = "${path.module}/scripts/load-dashboard.sh"
    destination = "/tmp/load-dashboard.sh"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = self.public_ip
    }
  }

  # Provisioner para ejecutar la configuración del dashboard
  provisioner "remote-exec" {
    inline = [
      "echo 'Esperando a que cloud-init termine...'",
      "cloud-init status --wait",
      "echo 'Cloud-init completado'",
      "echo 'Esperando a que Grafana esté instalado...'",
      "until systemctl list-unit-files | grep -q grafana-server.service; do echo 'Grafana aún no instalado, esperando...'; sleep 5; done",
      "echo 'Grafana instalado, configurando dashboard...'",
      "sudo mkdir -p /opt/grafana-dashboards",
      "sudo mkdir -p /var/lib/grafana/dashboards",
      "sudo mv /tmp/dashboard.json /opt/grafana-dashboards/dashboard.json",
      "sudo cp /opt/grafana-dashboards/dashboard.json /var/lib/grafana/dashboards/dashboard.json",
      "sudo chown grafana:grafana /var/lib/grafana/dashboards/dashboard.json",
      "sudo mv /tmp/load-dashboard.sh /opt/grafana-dashboards/load-dashboard.sh",
      "sudo chmod +x /opt/grafana-dashboards/load-dashboard.sh",
      "sudo bash -c 'cat > /etc/systemd/system/grafana-load-dashboard.service <<EOF\n[Unit]\nDescription=Load Grafana Dashboard\nAfter=grafana-server.service\nRequires=grafana-server.service\n\n[Service]\nType=oneshot\nExecStart=/opt/grafana-dashboards/load-dashboard.sh\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\nEOF'",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable grafana-load-dashboard.service",
      "sudo systemctl start grafana-load-dashboard.service",
      "echo 'Dashboard configurado exitosamente'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = self.public_ip
    }
  }
}

# Asociación de la Elastic IP a la instancia
resource "aws_eip_association" "grafana_eip_assoc" {
  instance_id   = aws_instance.ubuntu_grafana.id
  allocation_id = aws_eip.grafana_eip.id
}

# Outputs
output "influxdb_public_ip" {
  value = aws_instance.ubuntu_influxdb.public_ip
}

output "influxdb_private_ip" {
  value = aws_instance.ubuntu_influxdb.private_ip
}

output "grafana_public_ip" {
  value = aws_eip.grafana_eip.public_ip
}

output "grafana_private_ip" {
  value = aws_instance.ubuntu_grafana.private_ip
}

output "grafana_elastic_ip" {
  value = aws_eip.grafana_eip.public_ip
}

output "subnet_id_used" {
  value = aws_instance.ubuntu_influxdb.subnet_id
}

output "ssh_private_key_path" {
  value       = local_file.private_key.filename
  description = "Ruta al archivo de clave privada SSH"
}

output "ssh_connection_influxdb" {
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.ubuntu_influxdb.public_ip}"
  description = "Comando para conectar a la instancia InfluxDB"
}

output "ssh_connection_grafana" {
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_eip.grafana_eip.public_ip}"
  description = "Comando para conectar a la instancia Grafana"
}

output "grafana_url" {
  value       = "http://${aws_eip.grafana_eip.public_ip}:3000"
  description = "URL para acceder a Grafana (usuario: admin, contraseña: admin)"
}
