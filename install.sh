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

_pushd () {
    command pushd "$@" > /dev/null
}

_popd () {
    command popd > /dev/null
}

# The following option is not used, *unless*:
#    1) you want to install a valid version git ref
#       as a version not equal to that git ref e.g.
#       install plugin on git tag == 1.0.0 *as*
#       version 2.0.1 (for some reason)
#    2) you want to install from a git sha *as* the
#       version specified. If you want to install from
#       a git sha, the version defaults to 0.0.1
INSTALL_AS_VERSION="${3:-v0.0.1}"

V_VERSION_REGEX='^v.*[0-9]$'
# VERSION_REGEX='^.*[0-9]$'

# TODO: allow installing from a local file path

REPOSITORY="${1:-}"
if [[ -z ${REPOSITORY} ]]; then
  errxit "Full plugin name required e.g. 'github.com/phillbaker/terraform-provider-mailgunv3'"
fi

PLUGIN="$(basename "${REPOSITORY}")"
PLUGIN_SHORTNAME="${PLUGIN##*-}"

if [[ -d "${REPOSITORY}" ]]; then
  echo "Repository is to a local path."
elif [[ ! "${REPOSITORY}" =~ (:\/\/)|(^git@) ]]; then
   # if protocol not specified, use https
   # github and gitlab use 'git' user. address other use cases if/when they arise.
   REPOSITORY="https://"${REPOSITORY}
fi

echo "Installing from ${REPOSITORY}"

function get_latest_version {
  VERSIONS=($(git tag --list --format='%(refname:lstrip=2)' | grep -e ${V_VERSION_REGEX} | sort -r))
  if [ ${#VERSIONS[@]} -eq 0 ]; then
    errcho "No proper version tags found at ${REPOSITORY}. Using ${INSTALL_AS_VERSION}"
    echo "${INSTALL_AS_VERSION}"
  else
    errcho "Available Versions: ${VERSIONS[*]} (selecting latest)"
    echo "${VERSIONS[0]}"
  fi
}

TMPWORKDIR=$(mktemp -t='tf-installer' -d || errxit "Failed to create tmpdir.")
echo "Working in tmpdir ${TMPWORKDIR}"
_pushd "$TMPWORKDIR"
# clone plugin
_GITDIR="tf-installer-clone-${PLUGIN_SHORTNAME}"
git clone --quiet --depth 1 "${REPOSITORY}" "${_GITDIR}"
_pushd "${_GITDIR}"


git fetch --quiet --tags --update-head-ok

REVISION="${2:-$(get_latest_version)}"

# TODO(maybe): If revision was specified and matches VERSION_REGEX
#              but does not match V_VERSION_REGEX, prepend a 'v'.

echo "Building ${PLUGIN} version ${REVISION}"
_USING_HEAD=false
git checkout "${REVISION}" --quiet --force || _USING_HEAD=true

# If INSTALL_AS_VERSION was explicitly specified, it must be used.
# If the revision specified is not a valid version, use the fallback.
if [[ -n "${3:-}" ]] || ! [[ "${REVISION}" =~ ${V_VERSION_REGEX} ]] ; then
  VERSION="${INSTALL_AS_VERSION}"
  echo "Installing revision ${REVISION} as ${VERSION}"
else
  VERSION="${REVISION}"
fi

# In any case, double check that the VERSION used is valid.
if ! [[ "${VERSION}" =~ ${V_VERSION_REGEX} ]]; then
  errxit "${VERSION} is not a valid sem version ( ${V_VERSION_REGEX})"
fi

if ${_USING_HEAD}; then
  echo "Installing HEAD as ${VERSION}."
fi

go build -o "${HOME}/.terraform.d/plugins/${PLUGIN}_${VERSION}"
echo "Installing ${PLUGIN} version ${VERSION}"
echo "Terraform provider '${PLUGIN_SHORTNAME}' version ${VERSION} has been installed into ~/.terraform.d/"
_popd && _popd
