# terrraform-plugin-installer
A script to manage (future...) and install terraform plugins

Installs plugins as `terraform-provider-<NAME>_vX.Y.Z` to `~/.terraform.d/plugins`

## Usage

```
./install.sh <repository_url> <version/tag>
```

If no version/tag is provided, the latest release will be built and installed.

## Example

```
./install.sh github.com/samstav/terraform-provider-mailgunv3 v0.3.2
```

### Terraform configuration

```
...

provider "mailgunv3" {
  version = ">=0.3.2"
}

```
