environment = "prod"
location    = "centralus"
acr_sku     = "Premium"
aks_system_node_count = 1
aks_user_node_count   = 1
mongodb_vm_size       = "Standard_D8s_v3"
admin_source_ips      = ["99.113.26.153/32"]
api_server_authorized_ip_ranges = ["99.113.26.153/32"]
vnet_address_space = ["10.20.0.0/20"]
subnet_cidrs = {
  aks_system = "10.20.0.0/24"
  aks_user   = "10.20.1.0/24"
  appgw      = "10.20.2.0/24"
  data       = "10.20.3.0/24"
  ops        = "10.20.4.0/24"
}
aks_system_vm_size = "Standard_D2s_v6"
aks_user_vm_size   = "Standard_D2s_v6"
mongodb_admin_password = "!Azure!@#$"
linux_image = {
  publisher: "cognosys"
  offer: "ubuntu-18-04-lts-free"
  sku: "hardened-ubuntu-18-04-lts-freesku"
  version: "latest"
}
app_service_account_namespace = "navarapp"
wi_service_account_name       = "birthdayapp-sa"
arc_github_config_url         = "https://github.com/senavar/navar-demo"