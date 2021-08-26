#!/usr/bin/env bash

# Usage:
# ./install.sh github.com/owner/plugin <revision> <version>
#
# If <revision> matches a git tag specifying a semantic version
# the plugin will  be installed *as* that version.
#
# If the <version> argument is provided, the plugin will
# be installed as the version specified
#
# <revision> and <version> are not required, by default
# this script will install the latest version
#
# Installing from local paths is also supported, e.g.
#
#  ./install.sh /path/to/tf-plugin

# Undefined variables are errors.
set -euoE pipefail

errcho ()
{
    printf "%s\n" "$@" 1>&2
}

errxit ()
{
  errcho "$@"
  # shellcheck disable=SC2119
  errcleanup
}

debug ()
{
  if [ -n ${TF_PLUGIN_INSTALLER_DEBUG:-''} ]; then
    errcho "$@"
  fi
}

_pushd () {
    command pushd "$@" > /dev/null
}

_popd () {
    command popd > /dev/null
}

_cmd_exists () {
  if ! type "$*" &> /dev/null; then
    errcho "$* command not installed"
    return 1
  fi
}

_realpath () {
    if _cmd_exists realpath; then
      realpath "$@"
      return $?
    else
      readlink -f "$@"
      return $?
    fi
}

cleanup() {
  if [[ -d ${_tfpi_tmp_workdir:-} ]]; then
    # shellcheck disable=SC2086
    echo "Cleaning up tmp workdir [ ${_tfpi_tmp_workdir} ]"
    rm -rf "${_tfpi_tmp_workdir}"
    echo "🛀"
  fi
}

# shellcheck disable=SC2120
errcleanup() {
  errcho "⛔️ terraform plugin installer execution failed."
  if [ -n "${1:-}" ]; then
    errcho "⏩ Error at line ${1}."
  fi
  cleanup
  exit 1
}

intcleanup() {
  errcho "🍿 Script discontinued."
  cleanup
  exit 1
}

trap 'errcleanup ${LINENO}' ERR
trap 'intcleanup' SIGHUP SIGINT SIGTERM


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

if [[ -d "${REPOSITORY}" ]]; then
  echo "Source repository [ ${REPOSITORY} ] is to a local path. Attempting to discover remote URL."
  _pushd "$(_realpath "${REPOSITORY}")"
  # WARNING: WITHIN THIS BLOCK YOU ARE NOW IN A LOCAL REPOSITORY THAT SOMEONE PROBABLY CARES ABOUT.
  #          PERFORM EXCLUSIVELY READ-ONLY COMMANDS.
  _current_remote=$(git branch -vv --no-color | grep -e '^\*' | sed -E 's/.*\[(.*)\/[a-zA-Z0-9\ \:\,\_\.-]+\].*/\1/')
  REPOSITORY_URL=$(git remote get-url "${_current_remote}")
  echo "Discovered source url from local repo: ${REPOSITORY_URL}"
  _popd
else
  # If target is not a local filesytem path, check scheme
  if [[ ! "${REPOSITORY}" =~ (:\/\/)|(^git@) ]]; then
    # if the protocol/scheme is not specified, use 'https'
    # github and gitlab use 'git' user. address other use cases if/when they arise.
    REPOSITORY="https://"${REPOSITORY}
    REPOSITORY_URL="${REPOSITORY}"
  else
    # Provided url already includes scheme
    REPOSITORY_URL="${REPOSITORY}"
  fi
fi

REPO_REGEX='s/(.*:\/\/|^git@)(.*)([\/:]{1})([a-zA-Z0-9_\.-]{1,})([\/]{1})([a-zA-Z0-9_\.-]{1,}$)'

# Remove trailing .git if present
REPOSITORY_URL="${REPOSITORY_URL/%\.git/''}"
# the 2nd sed here is to parse out any user:<token> notations
REPOSITORY_URL_DOMAIN=$(echo "${REPOSITORY_URL}" | sed -E "${REPO_REGEX}"'/\2/' | sed -E "s/(^[a-zA-Z0-9_-]{0,38}\:{1})([a-zA-Z0-9_]{5,40})(\@?)"'//')
REPOSITORY_OWNER=$(echo "${REPOSITORY_URL}" | sed -E "${REPO_REGEX}"'/\4/')
REPOSITORY_PROJECT_NAME=$(echo "${REPOSITORY_URL}" | sed -E "${REPO_REGEX}"'/\6/')
PLUGIN_SHORTNAME=${REPOSITORY_PROJECT_NAME#"terraform-provider-"}
PLUGIN_SHORTNAME=${PLUGIN_SHORTNAME#"terraform-plugin-"}

debug "Provided Repository URL: ${REPOSITORY}"
debug "Repository URL: ${REPOSITORY_URL}"
debug "Repository URL Domain: ${REPOSITORY_URL_DOMAIN}"
debug "Repository Owner: ${REPOSITORY_OWNER}"
debug "Repository Project Name: ${REPOSITORY_PROJECT_NAME}"
debug "Plugin Shortname: ${PLUGIN_SHORTNAME}"

echo "Installing from ${REPOSITORY}"

function get_latest_version {
  VERSIONS=($(git tag --list --format='%(refname:lstrip=2)' | grep -e "${V_VERSION_REGEX}" | sort -r))
  if [ ${#VERSIONS[@]} -eq 0 ]; then
    errcho "No proper version tags found at ${REPOSITORY}. Using ${INSTALL_AS_VERSION}"
    echo "${INSTALL_AS_VERSION}"
  else
    errcho "Available Versions: ${VERSIONS[*]} (selecting latest)"
    echo "${VERSIONS[0]}"
  fi
}

_tfpi_tmp_workdir=$(mktemp -t='tfpi-workdir.XXXXXX' -d || errxit "Failed to create tmpdir.")
export _tfpi_tmp_workdir
echo "Working in tmpdir ${_tfpi_tmp_workdir}"
_pushd "${_tfpi_tmp_workdir}"
# clone plugin
_GITDIR="tf-installer-clone-${PLUGIN_SHORTNAME}"
git clone --quiet --depth 1 "${REPOSITORY}" "${_GITDIR}"
_pushd "${_GITDIR}"


git fetch --quiet --tags --update-head-ok

REVISION="${2:-$(get_latest_version)}"

# TODO(maybe): If revision was specified and matches VERSION_REGEX
#              but does not match V_VERSION_REGEX, prepend a 'v'.

echo "Building ${REPOSITORY_PROJECT_NAME} version ${REVISION}"
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

debug "Version: ${VERSION}"

if ${_USING_HEAD}; then
  echo "Installing HEAD as ${VERSION}."
fi

case "$OSTYPE" in
  darwin*)   _PLATFORM="darwin_amd64" ;;
  solaris*)  _PLATFORM="solaris_amd64" ;;
  linux*)    _PLATFORM="linux_amd64" ;;
  cygwin*)   _PLATFORM="windows_amd64" ;;
  *arm*)     _PLATFORM="linux_arm64" ;;
  *)         errxit "Unknown OSTYPE: ${OSTYPE}" ;;
esac

debug "Platform: ${_PLATFORM}"

# remove 'v' prefix if present for version dir in path
_version=${VERSION#"v"}
# path: HOSTNAME/NAMESPACE/TYPE/VERSION/TARGET
# e.g. -> /.terraform.d/plugins/github.internal.company.com/company/company_project/0.12.6/darwin_amd64
PLUGIN_TARGET="${HOME}/.terraform.d/plugins/${REPOSITORY_URL_DOMAIN}/${REPOSITORY_OWNER}/${PLUGIN_SHORTNAME}/${_version}/${_PLATFORM}/"
mkdir -p "${PLUGIN_TARGET}"

go build -o "${PLUGIN_TARGET}/${REPOSITORY_PROJECT_NAME}_${VERSION}"
echo "Installing ${REPOSITORY_PROJECT_NAME} version ${VERSION}"
echo "Terraform provider '${PLUGIN_SHORTNAME}' version ${VERSION} has been installed into ${PLUGIN_TARGET}"
_popd && _popd && cleanup
