terraform {
    backend "remote" {
        organization = "MyTerraform8892"

workspaces {
    name = "mytfeworksspace"
    }
  }
}
