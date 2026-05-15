variable "name" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.xlarge"
}

variable "subnet_id" {
  type = string
}

variable "key_pair_name" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "root_volume_size_gb" {
  type    = number
  default = 100
}

variable "data_volume_size_gb" {
  type    = number
  default = 200
}

variable "user_data" {
  type    = string
  default = ""
}
