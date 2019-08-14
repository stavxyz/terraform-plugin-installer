#!/usr/bin/env bash

# Undefined variables are errors.
set -euo pipefail

errcho ()
{
    echo "$@" 1>&2
}

errxit ()
{
  errcho "$@"
  exit 1
}

REPOSITORY="${1:-}"
if [[ -z ${REPOSITORY} ]]; then
  errxit "Full plugin name required e.g. 'github.com/phillbaker/terraform-provider-mailgunv3'"
fi

PLUGIN="$(basename ${REPOSITORY})"
PLUGIN_SHORTNAME="${PLUGIN##*-}"

if [[ ! "${REPOSITORY}" =~ "://" ]]; then
   REPOSITORY="https://"${REPOSITORY}
fi

function get_latest_version {
  git fetch --tags --update-head-ok --progress ${REPOSITORY}
  VERSIONS=($(git tag --list --format='%(refname:lstrip=2)' | grep -e '^v.*[0-9]$' | sort -r))
  >&2 echo "Available Versions: ${VERSIONS[*]} (selecting latest)"
  echo "${VERSIONS[0]}"
}

TMPWORKDIR=$(mktemp -t='tf-installer' -d || errxit "Failed to create tmpdir.")
echo "Working in tmpdir ${TMPWORKDIR}"
pushd $TMPWORKDIR
# clone plugin
_GITDIR="tf-installer-clone-${PLUGIN_SHORTNAME}"
git clone --depth 1 ${REPOSITORY} ${_GITDIR}
pushd ${_GITDIR}


VERSION="${2:-`get_latest_version`}"

git fetch --tags --update-head-ok --progress

echo "Building ${PLUGIN} version ${VERSION}"
git checkout ${VERSION} --force

go build -o "${HOME}/.terraform.d/plugins/${PLUGIN}_${VERSION}"
echo "Installing ${PLUGIN} version ${VERSION}"
echo "Terraform provider ${PLUGIN_SHORTNAME} version ${VERSION} has been installed to ~/.terraform.d/"
popd
popd
