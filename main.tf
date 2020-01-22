resource "azurerm_resource_group" "testrg" {
    name = "${var.name}"
    location = "${var.location}"
}