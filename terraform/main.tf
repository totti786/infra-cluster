terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    key = "ha-vps-cluster/terraform.tfstate"
  }
}

provider "digitalocean" {
  token = var.do_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Domain name for the cluster"
  type        = string
  default     = "example.com"
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "nyc1"
}

variable "ssh_keys" {
  description = "SSH key fingerprints"
  type        = list(string)
  default     = []
}

variable "lb_size" {
  description = "Load balancer node size"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "app_size" {
  description = "Application node size"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "db_size" {
  description = "Database node size"
  type        = string
  default     = "s-4vcpu-8gb"
}

variable "environment" {
  description = "Environment name (staging/production)"
  type        = string
  default     = "production"
}

locals {
  common_tags = [
    "Environment:${var.environment}",
    "ManagedBy:Terraform",
    "Project:HA-VPS-Cluster"
  ]
}

resource "digitalocean_ssh_key" "cluster_key" {
  count      = length(var.ssh_keys) == 0 ? 1 : 0
  name       = "ha-cluster-${var.environment}"
  public_key = file("~/.ssh/id_rsa.pub")
}

data "digitalocean_ssh_key" "cluster_keys" {
  count = length(var.ssh_keys)
  name  = var.ssh_keys[count.index]
}

resource "digitalocean_vpc" "cluster_vpc" {
  name     = "ha-cluster-vpc-${var.environment}"
  region   = var.region
  ip_range = "10.0.0.0/16"
}

resource "digitalocean_droplet" "load_balancer" {
  count  = 3
  image  = "ubuntu-22-04-x64"
  name   = "lb-${count.index + 1}-${var.environment}"
  region = var.region
  size   = var.lb_size
  
  vpc_uuid = digitalocean_vpc.cluster_vpc.id
  
  ssh_keys = length(var.ssh_keys) > 0 ? data.digitalocean_ssh_key.cluster_keys[*].id : [digitalocean_ssh_key.cluster_key[0].id]
  
  tags = concat(local.common_tags, ["Role:LoadBalancer"])

  connection {
    host        = self.ipv4_address
    type        = "ssh"
    user        = "root"
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y python3",
    ]
  }
}

resource "digitalocean_droplet" "application" {
  count  = 3
  image  = "ubuntu-22-04-x64"
  name   = "app-${count.index + 1}-${var.environment}"
  region = var.region
  size   = var.app_size
  
  vpc_uuid = digitalocean_vpc.cluster_vpc.id
  
  ssh_keys = length(var.ssh_keys) > 0 ? data.digitalocean_ssh_key.cluster_keys[*].id : [digitalocean_ssh_key.cluster_key[0].id]
  
  tags = concat(local.common_tags, ["Role:Application"])

  connection {
    host        = self.ipv4_address
    type        = "ssh"
    user        = "root"
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y python3",
    ]
  }
}

resource "digitalocean_droplet" "database" {
  count  = 2
  image  = "ubuntu-22-04-x64"
  name   = "db-${count.index + 1}-${var.environment}"
  region = var.region
  size   = var.db_size
  
  vpc_uuid = digitalocean_vpc.cluster_vpc.id
  
  ssh_keys = length(var.ssh_keys) > 0 ? data.digitalocean_ssh_key.cluster_keys[*].id : [digitalocean_ssh_key.cluster_key[0].id]
  
  tags = concat(local.common_tags, ["Role:Database"])

  connection {
    host        = self.ipv4_address
    type        = "ssh"
    user        = "root"
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y python3",
    ]
  }
}

resource "digitalocean_droplet" "redis" {
  count  = 3
  image  = "ubuntu-22-04-x64"
  name   = "redis-${count.index + 1}-${var.environment}"
  region = var.region
  size   = "s-2vcpu-4gb"
  
  vpc_uuid = digitalocean_vpc.cluster_vpc.id
  
  ssh_keys = length(var.ssh_keys) > 0 ? data.digitalocean_ssh_key.cluster_keys[*].id : [digitalocean_ssh_key.cluster_key[0].id]
  
  tags = concat(local.common_tags, ["Role:Redis"])
}

resource "digitalocean_reserved_ip" "floating_ip" {
  region = var.region
}

resource "digitalocean_floating_ip_assignment" "main" {
  ip_address = digitalocean_reserved_ip.floating_ip.ip_address
  droplet_id = digitalocean_droplet.load_balancer[0].id
}

resource "digitalocean_firewall" "load_balancer" {
  name = "lb-firewall-${var.environment}"
  
  droplet_ids = digitalocean_droplet.load_balancer[*].id

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "vrrp"
    source_addresses = [digitalocean_vpc.cluster_vpc.ip_range]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "digitalocean_firewall" "application" {
  name = "app-firewall-${var.environment}"
  
  droplet_ids = digitalocean_droplet.application[*].id

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = [digitalocean_vpc.cluster_vpc.ip_range]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = [digitalocean_vpc.cluster_vpc.ip_range]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = [digitalocean_vpc.cluster_vpc.ip_range]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "digitalocean_firewall" "database" {
  name = "db-firewall-${var.environment}"
  
  droplet_ids = digitalocean_droplet.database[*].id

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = [digitalocean_vpc.cluster_vpc.ip_range]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "5432"
    source_addresses = [digitalocean_vpc.cluster_vpc.ip_range]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = [digitalocean_vpc.cluster_vpc.ip_range]
  }
}

resource "cloudflare_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  value   = digitalocean_reserved_ip.floating_ip.ip_address
  type    = "A"
  ttl     = 60
  proxied = true
}

resource "cloudflare_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  value   = var.domain
  type    = "CNAME"
  ttl     = 60
  proxied = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
  default     = ""
}

output "floating_ip" {
  value = digitalocean_reserved_ip.floating_ip.ip_address
}

output "load_balancer_ips" {
  value = digitalocean_droplet.load_balancer[*].ipv4_address
}

output "application_ips" {
  value = digitalocean_droplet.application[*].ipv4_address
}

output "database_ips" {
  value = digitalocean_droplet.database[*].ipv4_address
}

output "redis_ips" {
  value = digitalocean_droplet.redis[*].ipv4_address
}

output "vpc_ip_range" {
  value = digitalocean_vpc.cluster_vpc.ip_range
}
