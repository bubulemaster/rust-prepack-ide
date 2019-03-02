#!/bin/bash
print_ok() {
  echo " ${GREEN}✔${RESET}"
}

print_ko() {
  echo " ${RED}✗${RESET}"
}

find_lastest_date_with_rls() {
  #date -d "19:00 today - 1 days" +'%Y-%m-%d %H:%M:%S'
  local check_date="$1"
  local arch="$2"
  local filename=/tmp/channel-rust-nightly.toml

  curl https://static.rust-lang.org/dist/${check_date}/channel-rust-nightly.toml --output ${filename} 2>/dev/null

  local line_number=$(cat "${filename}" | grep -n '\[pkg.rls-preview.target.'${arch}'\]' | cut -d ':' -f 1)
  line_number="$(expr ${line_number} + 1)"

  # Hope last line is 'available'
  local line="$(sed ${line_number}'!d' "${filename}" | grep 'available')"

  rm -f "${filename}"

  if [ -n "${line}" ]; then
    local available=$(echo ${line} |  cut -d '=' -f 2 | xargs)

    echo "${available}"
  else
    echo "false"
  fi
}

find_rust_channel() {
  local arch="$(rustup show | grep 'Default host:' | cut -d ':' -f 2 | xargs)"

  echo "Search last available date of nightly channel for rls-preview"

  # rls-preview never available on current day
  local count=1

  while [ ${count} -lt 30 ]; do
    local current_date="$(date -d '19:00 today - '${count}' days' +'%Y-%m-%d')"

    echo -n "Check for nightly-${current_date}..."

    is_ok=$(find_lastest_date_with_rls ${current_date} ${arch})

    if [ "${is_ok}" = "true" ]; then
      print_ok
      CHANNEL="nightly-${current_date}"
      return
    else
      print_ko
    fi

    count=$(expr ${count} + 1)
  done

  CHANNEL=""
}

install_rustup_components() {
  local rustup_components="$1"
  local channel=""

  if [ -n "$2" ]; then
    channel="--toolchain $2"
  fi

  local current_rustup_components="$(rustup component list)"
  local is_installed=""

  # Install cargo components
  if [ -n "${rustup_components}" ]; then
    for pck_name in ${rustup_components}; do
      # Check if package is installed
      is_installed=$(echo $current_rustup_components | grep "${pck_name}")

      if [ -n "${is_installed}" ]; then
        echo -n "Rustup package '${pck_name}' already installed"
        print_ok
      else
        rustup component add "${pck_name}" ${channel}
      fi
    done
  fi
}

install_cargo_components() {
  local cargo_components="$1"
  local channel=""

  if [ -n "$2" ]; then
    channel="+$2"
  fi

  local current_cargo_components="$(cargo install --list)"
  local is_installed=""

  # Install cargo components
  if [ -n "${cargo_components}" ]; then
    for pck_name in ${cargo_components}; do
      # Check if package is installed
      is_installed=$(echo ${current_cargo_components} | grep "${pck_name}")

      if [ -n "${is_installed}" ]; then
        echo -n "Cargo package '${pck_name}' already installed"
        print_ok
      else
        cargo ${channel} install "${pck_name}"
      fi
    done
  fi
}

set_channel_in_atom_editor() {
  filename="${HOME}/.atom/config.cson"
  local line_number=$(cat "${filename}" | grep -n 'rlsToolchain' | cut -d ':' -f 1)
  sed -i ${line_number}'s/.*/    rlsToolchain: "'$1'"/' "${filename}"
}

RED=`tput setaf 1`
GREEN=`tput setaf 2`
RESET=`tput sgr0`

REALPATH="$(realpath $0)"
BASEDIR="$(dirname ${REALPATH})"

. "${BASEDIR}/../config.cfg"

sudo chown -R ${USERNAME_TO_RUN}:${USERNAME_TO_RUN} ${RUST_HOME}

# Check if need install rust
if [ ! -f "${CARGO_BIN}/rustup" ]; then
  curl https://sh.rustup.rs -sSf -o /tmp/install-rust.sh
  chmod u+x /tmp/install-rust.sh

  /tmp/install-rust.sh --no-modify-path -v -y
  rm /tmp/install-rust.sh
fi

# Install stable version if set
if [ -n "${RUST_STABLE_CHANEL_VERSION}" ] && [ -z "$(rustup show | grep ${RUST_STABLE_CHANEL_VERSION})" ]; then
  echo ${CARGO_BIN}/rustup install "${RUST_STABLE_CHANEL_VERSION}"
fi

find_rust_channel

if [ -z "${CHANNEL}" ]; then
  echo "Can't find a valid nightly channel for 'rls-preview'!" >&2
  exit 1
fi

install_rustup_components "rls-preview rls rust-analysis rust-src"
install_rustup_components "${RUSTUP_COMPONENTS}"

rustup install nightly
rustup install "${CHANNEL}"

install_rustup_components "rls-preview rls rust-analysis rust-src" "${CHANNEL}"

install_cargo_components "racer" "nightly"
install_cargo_components "${CARGO_COMPONENTS}"

# Replace channel in atom-editor
set_channel_in_atom_editor "${CHANNEL}"
