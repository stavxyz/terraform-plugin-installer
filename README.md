# terrraform-plugin-installer
It's a script to install third party terraform plugins! Hassle free! How neat is that?

Installs plugins as `terraform-provider-<NAME>_vX.Y.Z` to `~/.terraform.d/plugins`

See more on third party plugin installation here: https://www.terraform.io/docs/configuration/providers.html#third-party-plugins

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
