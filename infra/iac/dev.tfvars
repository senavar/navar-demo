environment = "dev"
location    = "canadacentral"
acr_sku     = "Premium"
aks_system_node_count = 1
aks_user_node_count   = 1
mongodb_vm_size       = "Standard_B2ls_v2"
admin_source_ips      = ["99.113.26.153/32"]
api_server_authorized_ip_ranges = ["99.113.26.153/32"]
vnet_address_space = ["10.10.0.0/20"]
subnet_cidrs = {
  aks_system = "10.10.0.0/24"
  aks_user   = "10.10.1.0/24"
  appgw      = "10.10.2.0/24"
  data       = "10.10.3.0/24"
  ops        = "10.10.4.0/24"
}
aks_system_vm_size = "Standard_B2ls_v2"
aks_user_vm_size   = "Standard_B2ls_v2"
mongodb_admin_password = "!Azure!@#$"
linux_image = {
  "publisher": "canonical",
  "offer": "0001-com-ubuntu-server-jammy",
  "sku": "22_04-lts-gen2",
  "version": "latest"
}
app_service_account_namespace = "birthdayapp"
wi_service_account_name       = "birthdayapp-sa"
arc_github_config_url         = "https://github.com/senavar/navar-demo"