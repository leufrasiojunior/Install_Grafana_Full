#!/bin/bash
# shellcheck disable=SC2034
# -e option instructs bash to immediately exit if any command [1] has a non-zero exit status
# We do not want users to end up with a partially working install, so we exit the script
# instead of continuing the installation with something broken
clear
set -e

# dialog dimensions: Let dialog handle appropriate sizing.
screen_size="$(stty size 2>/dev/null || echo 24 80)"
rows="$(echo "${screen_size}" | awk '{print $1}')"
columns="$(echo "${screen_size}" | awk '{print $2}')"
# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$((rows / 2))
c=$((columns / 2))

#Set PKG Manager
PKG_MANAGER="apt-get"
UPDATE_PKG_CACHE="${PKG_MANAGER} update"
PKG_INSTALL=("${PKG_MANAGER}" -qq install)

# Set these values so the installer can still run in color
COL_NC='\e[0m' # No Color
COL_LIGHT_GREEN='\e[1;32m'
COL_LIGHT_RED='\e[1;31m'
TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
INFO="[i]"
# shellcheck disable=SC2034
DONE="${COL_LIGHT_GREEN} done!${COL_NC}"
OVER="\\r\\033[K"

#Deps do install
INSTALL_DEPS=(curl wget whiptail)

#Links
REPO_PROMETHEUS=("https://api.github.com/repos/prometheus/node_exporter/releases/latest")

is_command() {
	# Checks to see if the given command (passed as a string argument) exists on the system.
	# The function returns 0 (success) if the command exists, and 1 if it doesn't.
	local check_command="$1"

	command -v "${check_command}" >/dev/null 2>&1
}

os_check() {
	detected_os=$(grep '^ID=' /etc/os-release | cut -d '=' -f2 | tr -d '"')
	detected_version=$(grep VERSION_ID /etc/os-release | cut -d '=' -f2 | tr -d '"')
	if [ "$detected_os" == "debian" ] && [ "$detected_version" -ge 12 ]; then
		return 0
	else
		echo "System not tested. Exiting install"
		return 1
	fi
}

spinner() {
	local pid=$1
	local delay=0.10
	local spinstr='/-\|'
	while ps a | awk '{print $1}' | grep -q "$pid"; do
		local temp=${spinstr#?}
		printf " [%c]  " "${spinstr}"
		local spinstr=${temp}${spinstr%"$temp"}
		sleep ${delay}
		printf "\\b\\b\\b\\b\\b\\b"
	done
	printf "    \\b\\b\\b\\b"

	# &>> /dev/null & spinner $!
	#&>> /var/log/install.log & spinner $!
}

update_package_cache() {
	# Update package cache on apt based OSes. Do this every time since
	# it's quick and packages can be updated at any time.

	# Local, named variables
	local str="Update local cache of available packages"
	printf "  %b %s..." "${INFO}" "${str}"
	# Create a command from the package cache variable
	if eval " ${SUDO} ${UPDATE_PKG_CACHE}" &>/dev/null; then
		printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
	else
		# Otherwise, show an error and exit

		# In case we used apt-get and apt is also available, we use this as recommendation as we have seen it
		# gives more user-friendly (interactive) advice
		if [[ ${PKG_MANAGER} == "apt-get" ]] && is_command apt; then
			UPDATE_PKG_CACHE="apt update"
		fi
		printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
		printf "  %b Error: Unable to update package cache. Please try \"%s\"%b\\n" "${COL_LIGHT_RED}" "sudo ${UPDATE_PKG_CACHE}" "${COL_NC}"
		return 1
	fi
}

# Let user know if they have outdated packages on their system and
# advise them to run a package update at soonest possible.
notify_package_updates_available() {
	# Local, named variables
	local str="Checking ${PKG_MANAGER} for upgraded packages"
	printf "\\n  %b %s..." "${INFO}" "${str}"
	# Store the list of packages in a variable
	updatesToInstall=$(eval "${PKG_COUNT}")

	if [[ -d "/lib/modules/$(uname -r)" ]]; then
		if [[ "${updatesToInstall}" -eq 0 ]]; then
			printf "%b  %b %s... up to date!\\n\\n" "${OVER}" "${TICK}" "${str}"
		else
			printf "%b  %b %s... %s updates available\\n" "${OVER}" "${TICK}" "${str}" "${updatesToInstall}"
			printf "  %b %bIt is recommended to update your OS after installing the Pi-hole!%b\\n\\n" "${INFO}" "${COL_LIGHT_GREEN}" "${COL_NC}"
		fi
	else
		printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
		printf "      Kernel update detected. If the install fails, please reboot and try again\\n"
	fi
}

get_available_releases() {

	MY_KERNEL=$(uname -s | tr '[:upper:]' '[:lower:]')
	# shellcheck disable=SC2128
	TYPEPROM=$(curl -s "${REPO_PROMETHEUS}" | grep browser_download_url | grep "${MY_KERNEL}" | cut -d '"' -f 4 | rev | cut -d "/" -f 1 | rev)

	ChooseOptions=()
	ServerCount=0
	# Save the old Internal Field Separator in a variable
	OIFS=$IFS
	# and set the new one to newline
	IFS=$'\n'
	# Put the DNS Servers into an array
	for VERSION in ${TYPEPROM}; do
		TYPE="$(cut -d':' -f2 <<<"${VERSION}")"
		ChooseOptions[ServerCount]="${TYPE}"
		((ServerCount = ServerCount + 1))
		ChooseOptions[ServerCount]=""
		((ServerCount = ServerCount + 1))
	done
	# Restore the IFS to what it was
	IFS=${OIFS}
	ARCHITECTURE=$(dpkg --print-architecture)
	# In a whiptail dialog, show the options
	OSchoices=$(whiptail --backtitle "Select version to download" --separate-output --menu "select the file name according to your system architecture. Currently your system uses: ""${MY_KERNEL}"" ""${ARCHITECTURE}""" ${r} ${c} 10 \
		"${ChooseOptions[@]}" 2>&1 >/dev/tty) ||
		# exit if Cancel is selected
		{
			# shellcheck disable=SC2183
			str="Process cancelled. Exiting..."
			printf "  %b %s..." "${INFO}" "${str}"
			exit 1
		}

	#Create directory to temp File
	mkdir -p /tmp/node
	# shellcheck disable=SC2128
	str="Wait download process to "
	printf "  %b %s %s...\\n" "${INFO}" "${str}" "${OSchoices}"
	curl -s "${REPO_PROMETHEUS[@]}" | grep browser_download_url | grep "${OSchoices}" | cut -d '"' -f 4 | wget -qi - -P "/tmp/node"
}

configure_node() {

	EXTRACT=$(
		tar xf /tmp/node/node_exporter*.tar.gz -C /tmp/node/ --strip-components=1
	)
	local str="Extract files. Wait process finish"
	printf "  %b %s...\\n" "${INFO}" "${str}"
	# Create a command from the package cache variable
	if eval " ${SUDO} ${EXTRACT}"; then
		printf "%b  %b %s\\n" "${OVER}" "${TICK}" "${str}"
	else
		printf "%b  %b %s\\n" "${OVER}" "${CROSS}" "${str}"
		echo "Verify log"
	fi

	${SUDO} cp /tmp/node/node_exporter /usr/local/bin
}

verify_users() {
	if (getent passwd prometheus >/dev/null); then
		local str="user prometheus already created previously"
		printf "%b  %b %s\\n" "${OVER}" "${INFO}" "${str}"
		return 0
	else
		#Create user before install Node Exporter.
		groupadd --system prometheus
		useradd -s /sbin/nologin --system -g prometheus prometheus
	fi
}

create_systemd_services() {
	${SUDO} cat <<EOF >/etc/systemd/system/node_exporter.service
[Unit]

Description=Node Exporter
Want)=network-online.target
After=network-online.target

[Service]

User=prometheus
ExecStart=/sr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

	${SUDO} systemctl daemon-reload
	${SUDO} systemctl start node_exporter
	${SUDO} systemctl enable node_exporter

	#Check installation prometheus to configure YAML.
	if (which prometheus >/dev/null); then
		${SUDO} cat <<EOF >>/etc/prometheus/prometheus.yml
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF
		${SUDO} systemctl restart prometheus
	fi
}
main() {

	if [[ "${EUID}" -eq 0 ]]; then
		# they are root and all is good
		local str="Root user check"
		printf "  %b %s\\n" "${TICK}" "${str}"
	else
		printf "  %b %bScript called with non-root privileges%b\\n" "${INFO}" "${COL_LIGHT_RED}" "${COL_NC}"
		printf "  %b Sudo utility check" "${INFO}"
		# If the sudo command exists, try rerunning as admin
		if is_command sudo; then
			printf "%b  %b Sudo utility check\\n" "${OVER}" "${TICK}"
			if [[ "$0" == "bash" ]]; then
				# Download the install script and run it with admin rights
				exec curl -sSL https://raw.githubusercontent.com/leufrasiojunior/Install_Grafana_Full/main/Install_Node-Exporter.sh | sudo bash "$@"
			else
				# when run via calling local bash script
				exec sudo bash "$0" "$@"
			fi
		fi
	fi
	update_package_cache &
	spinner $!

	notify_package_updates_available &
	spinner $!

	sleep 2
	get_available_releases
	verify_users
	configure_node
	create_systemd_services
	local str="Instalattion finished. Use this IP to access Metrics:"
	IPv4bare="127.0.0.1"
	IPV4_ADDRESS=$(ip -oneline -family inet address show | grep "${IPv4bare}/" | awk '{print $4}' | awk 'END {print}')
	printf "	%b  %b %s\\n" "${OVER}" "${INFO}" "http://${IPV4_ADDRESS%/*}:9100/metrics"

}

if [[ "${SKIP_INSTALL}" != true ]]; then
	main "$@"
fi
