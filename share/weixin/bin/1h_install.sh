#!/bin/bash
# 1H - 1h_install.sh								Copyright(c) 2010 1H Ltd.
#														 All rights Reserved.
# copyright@1h.com							 			   http://www.1h.com
# This code is subject to the 1H license. Unauthorized copying is prohibited.

VERSION='2.50.14'

# Ensure that all standard paths are exported
export PATH='/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin'

if [ "$(whoami)" != 'root' ]; then
	echo "Sorry but $0 should be executed as root"
	exit 1
fi

# Some fancy vars here :)
BEEP="\x07"
ESC="\x1b["
RED=$ESC"31;01m"
GREEN=$ESC"32;01m"
YELLOW=$ESC"33;01m"
DBLUE=$ESC"34;01m"
MAGENTA=$ESC"35;01m"
BLUE=$ESC"36;01m"
WHITE=$ESC"37;01m"
GREY=$ESC"30;01m"
RESET=$ESC"39;49;00m"
BOLD="\033[1m"

reports_mail='installation-reports@1h.com'
check_log='/var/log/1h.log'
mkdir -p /var/log/
echo "--- Started on $(date) ---" >> ${check_log}

# Increase the default ulimits
ulimit \
	-c 1000000 \
	-f unlimited \
	-i 38912 \
	-l 2048 \
	-n 50000 \
	-q 819200 \
	-s 28670 \
	-t unlimited \
	-u 3583 \
	-x unlimited \
	-m unlimited \
	-d unlimited \
	-v unlimited >> ${check_log} 2>&1

# Distro name
distro=''
# CPU arch vars
arch=''
os_arch=''
# OS vars
os_major=''
os_minor=''

# URLs we need
client_api="http://license.1h.com/client_api.pl"
repo_url='http://sw.1h.com/centos/1h-repository.noarch.rpm'

# Used for automated installations
auto_agreement='/root/1h.software.agreement.auto.install'

# Control panel name
control_panel=''

# Running web server global vars
webserver_type=""
webserver_version=""
webserver_conf=""
webserver_init=""

# Hive related global vars
# Hive pkg_name is empty by default
hive_pkg_name=''
# We should never remove the rpm installed httpd by default
remove_rpm_httpd=0
# nss ldap should be removed if it is installed
remove_nss_ldap=0

# Other global vars
install_mysql_devel=0
# Crond should not be installed by default (unless requested)
install_crond=0
# Do not try to adjust kernel.pid_max by default. Only if needed :)
adjust_max_pid=0
max_pid_limit=65535
normal_pid_limit=32768
sysctl_conf='/etc/sysctl.conf'
# PostgreSQL needs kernel.shmmax to be at least $required_shmmax bytes.
# Do not adjust it by default. adjust_shmmax will be 1 only if kernel.shmmax < $required_shmmax
adjust_shmmax=0
required_shmmax=67108864
# Shall we disable statfs for cPanel servers when we are installing Hive?
disable_statfs=0
statfs_conf='/var/cpanel/disablestatfs'

# Fix perl permissions
fix_perl_perms=0
perl_path=$(which perl 2>/dev/null)

server_changes=""
changes_counter=0

# By Default postgresql package name should be 84
# For rhel/centos 6+ the name of the psql 8.4 package is simply postgres
psql_pkg_suffix="84"

# cPanel Shell Fork Bomb Protection files
ulimit_files='/etc/bashrc /etc/profile /etc/profile.d/limits.sh'
ulimit_fix=0

should_stop_guardian=0
should_relock_configs=0
should_revert_fastmirror=0

# The following vars will be used by doUnlockConfigs function
# Declare the configs we will scan and which might be locked
declare -a configs_to_unlock=('/etc/yum.conf' '/etc/yum/pluginconf.d/fastestmirror.conf')
# If any of the configs defined above is locked with certain fs attribs the attribs will be stored in the array below
# They will be stored in the same position as the position of the conf itself so we have a nice 2 arrays which looks almost like hash :)
# Declare an empty array which will store attribs for each config
declare -a configs_to_unlock_attribs=()

function usage {
	echo "$0 [portal|guardian|hive|digits|hawk|all]"
	echo ""
	echo -e "\tportal\t\t- Install 1H central monitoring interface Portal"
	echo -e "\tguardian\t- Install 1H Guardian monitoring and reaction system"
	echo -e "\thive\t\t- Install 1H Hive"
	echo -e "\tdigits\t\t- Install 1H Digits disk usage and network traffic statistics (cPanel support only)"
	echo -e "\thawk\t\t- Install 1H Hawk IDS/IPS (intrusion detection, prevention and protection system)"
	echo -e "\tall\t\t- Install guardian, hive, digits (only on cPanel) and hawk at a single shot. 1H portal can not be installed in all. It should be installed separately."
	exit 1
}

if [ $# -ne 1 ]; then
	usage
fi

if [[ ! "$1" =~ ^(portal|guardian|hive|digits|hawk|all)$ ]]; then
	usage
fi

install_pkg="$1"

function show_info {
	echo -e "${GREEN}[${WHITE}+${GREEN}]${DBLUE} ${1}:${GREEN} ${2}${RESET}"
	echo -e "[+] ${1}: ${2}" >> ${check_log}
}

function askConfirmation {
	echo -e -n "${GREEN}[${WHITE}?${GREEN}] ${DBLUE}${1} ${WHITE}[y/N]:${RESET} "
	read response
	if [[ ! "$response" =~ ^(y|yes|YES|Y|ye|yeS|YeS|Yes|YEs|YeS|yES)$ ]]; then
		show_error "$install_pkg installations" "Canceled by user"
	fi
}

function send_mail {
	echo -e -n "${GREEN}[${WHITE}?${GREEN}] ${DBLUE}Do you agree to send the output report to $reports_mail ${WHITE}[Y/n]:${RESET} "
	read response
	if [[ ! "$response" =~ ^(n|no|NO|nO|No)$ ]]; then
		show_info "Sending the mail" "... to $reports_mail ..."
		cat "$check_log" | mail -s "1H Preinstall Checks for $(hostname)" "$reports_mail"
		show_info "Mail sent" "to $reports_mail" 
	else
		show_info "Sending output report to $reports_mail" "Canceled by user"
	fi
	show_info "Thank you very much for your kind support" "http://www.1h.com team. We optimize your hosting business!"
}

function show_error {
	if [ "$should_stop_guardian" == "1" ]; then
		show_info "Starting guardian" "which we stopped prior this installation attempt"
		guardian_init start
	fi

	# Enable yum fastest mirror plugin if we disabled it prior the install
	if [ "${distro}" != 'debian' ] && [ "$should_revert_fastmirror" == "1" ]; then
		changeFastMirrorStatus 1 0
	fi

	# If show_error is called by the doRelockConfigs function itself (unlock fails) should_relock_configs is zeroed right before the error call.
	# This should prevent endless loops betwen doRelockConfigs and show_error
	if [ "$should_relock_configs" == "1" ]; then
		doRelockConfigs
	fi

	echo -e "${RED}[${WHITE}!${RED}]${DBLUE} ${1}:${RED} ${2}${RESET}${BEEP}"
	echo -e "[!] ${1}: ${2}" >> ${check_log}
	send_mail
	exit 1
}

function show_warning {
	#echo -e "${YELLOW}[${WHITE}w${YELLOW}]${DBLUE} ${1}:${YELLOW} ${2}${RESET}${BEEP}"
	echo -e "[w] ${1}: ${2}" >> ${check_log}
	server_changes[$changes_counter]=$(echo -e "${YELLOW}[${WHITE}w${YELLOW}]${DBLUE} ${1}:${YELLOW} ${2}${RESET}${BEEP}")
	let changes_counter=$changes_counter+1
}

function check_arch {
	arch=$(uname -m)
	if [ "$arch" == "i686" ] || [ "$arch" == "i386" ]; then
		os_arch='x86'
	elif [ "$arch" == "x86_64" ]; then
		os_arch='x86_64'
	else
		show_error "CPU Architecture" "Not supported."
	fi
	show_info "CPU Architecture" "PASSED"
}

function quit_incompatible_os {
	show_error "OS compatibility" "OS distribution is not compatible. DO NOT PROCEED WITH 1H SOFTWARE INSTALLATION."
}

function check_os {
	# Check for redhat/cent/debian machines
	if [ -f /etc/redhat-release ]; then
		release=$(cat /etc/redhat-release)
		
		if [[ "${release}" =~ CentOS ]]; then
			distro='centos'
		elif [[ "${release}" =~ 'Red Hat' ]]; then
			distro='redhat'
		elif [[ "${release}" =~ CloudLinux ]]; then
			distro='cloudlinux'
		else
			quit_incompatible_os
		fi
	
		os_major=$(echo ${release} | sed 's/.*\([0-9]\+\.[0-9]\+\).*/\1/' | awk -F . '{print $1}')
		os_minor=$(echo ${release} | sed 's/.*\([0-9]\+\.[0-9]\+\).*/\1/' | awk -F . '{print $2}')
	
		# Make sure that the RHEL/CentOS versions are at least 5.3. < 5.3 is not supported.
		if [ "${os_major}" -lt 5 ]; then
			quit_incompatible_os
		elif [ "${os_major}" -eq 5 ] && [ "${os_minor}" -lt 3 ]; then
			quit_incompatible_os
		fi
	
		if [ "${os_major}" -eq 6 ]; then
			# Do not append suffix to the postgresql package names for CentOS/RHEL 6+.
			psql_pkg_suffix=""
		fi
	elif [ -f /etc/debian_version ]; then
		distro='debian'

		release=$(cat /etc/debian_version)

		os_major=$(echo ${release} | sed 's/.*\([0-9]\.[0-9]\.[0-9]\).*/\1/' | awk -F . '{print $1}')
		os_minor=$(echo ${release} | sed 's/.*\([0-9]\.[0-9]\.[0-9]\).*/\1/' | awk -F . '{print $2}')

		# Currently we support only debian 6 or above.
		if [ -z "${os_major}" ] || [ "${os_major}" -lt 6 ]; then
			quit_incompatible_os
		fi
	else
		quit_incompatible_os
	fi

	show_info "OS compatibility" "PASSED"
}

function get_psql_version {
	psql_bin=$(which psql 2>/dev/null)

	if [ -z "${psql_bin}" ]; then
		exit 0
	fi

	if [ ! -x "${psql_bin}" ]; then
		exit 0
	fi

	psql_version=$(${psql_bin} -V 2>/dev/null | awk '/^psql/{print $3}')

	if [ -z "${psql_version}" ]; then
		exit 0
	fi

	echo "${psql_version}"
}

function get_psql_branch {
	psql_branch=$(get_psql_version | awk -F . '{print $1"."$2}')

	if [ -z "${psql_branch}" ]; then
		exit 0
	fi

	echo "${psql_branch}"
}

function get_psql_data_dir {
	if [ "${distro}" == 'debian' ]; then
		psql_branch=$(get_psql_branch)
		psql_data_dir="/var/lib/postgresql/${psql_branch}/main"
	else
		psql_data_dir="/var/lib/pgsql/data"
	fi

	if [ ! -d "${psql_data_dir}" ]; then
		exit 0
	fi

	echo "${psql_data_dir}"
}

function get_pghba_conf {
	if [ "${distro}" == 'debian' ]; then
		psql_branch=$(get_psql_branch)
		pghba_conf="/etc/postgresql/${psql_branch}/main/pg_hba.conf"
	else
		pghba_conf='/var/lib/pgsql/data/pg_hba.conf'
	fi

	if [ ! -f "${pghba_conf}" ]; then
		exit 0
	fi

	echo "${pghba_conf}"
}

function get_psql_init {
	init_list='/etc/init.d/postgresql /etc/init.d/postgres /etc/init.d/psql'
	for init_script in ${init_list}; do
		if [ ! -x "${init_script}" ]; then
			continue
		fi
		psql_init="${init_script}"
		break
	done

	if [ -z "${psql_init}" ]; then
		exit 0
	fi

	echo "${psql_init}"
}

function bruteforce_web_bin {
	#echo "No running web servers found. We should bruteforce some binary paths here."
	web_bin_paths='/usr/local/apache/bin /usr/local/lsws/bin /opt/lsws/bin /usr/sbin /usr/bin /usr/local/bin /usr/local/apache2/bin /usr/local/sbin /usr/local/httpd/bin'
	web_bins='httpd lshttpd'

	# Some of the litespeed binaries are packed with upx thus /proc/self/exe does not point to the exact path of the litespeed binary
	# Let us first try to guess if this is a litespeed and if so try bruteforcing only known lsws paths.
	if ( ps uaxwf | grep -v grep | grep -i litespeed >> ${check_log} 2>&1 ); then
		web_bins='lshttpd'
		web_bin_paths='/usr/local/lsws/bin /opt/lsws/bin /usr/sbin /usr/bin /usr/local/bin /usr/local/sbin'
	fi

	for web_bin_path in $web_bin_paths; do
		for web_bin in $web_bins; do
			if [ ! -x $web_bin_path/$web_bin ]; then
				continue
			fi
			# If we are here then we find binary file with a known name in certain location. We should move ahead then
			webserver_bin_path="$web_bin_path/$web_bin"
			# This will break the chains of both of the loops
			break 2
		done
	done
	echo "$webserver_bin_path"
}

function identify_web_server_type {
	#echo "Web cmd: $webserver_bin_path Short cmd: $webserver_bin_basename"
	webserver_bin_basename="$1"

	if [[ "$webserver_bin_basename" =~ ^lshttpd.* ]]; then
		webserver_type='litespeed'
		webserver_version=$($webserver_bin_path -v | sed 's/.*\/\(.*\) .*/\1/g')
		webserver_coredir=$(dirname $webserver_bin_path | sed 's/\/bin//g')
		webserver_conf="$webserver_coredir/conf/httpd_config.xml"
	
		# If the current found lsws core dir is NOT /usr/local/lsws but /usr/local/lsws exist on the server:
		# - move /usr/local/lsws to a backup dir
		# - symlink /usr/local/lsws to the current $webserver_coredir
		if [ "$webserver_coredir" != "/usr/local/lsws" ]; then
			if [ -h "/usr/local/lsws" ]; then
				unlink /usr/local/lsws >> ${check_log} 2>&1
			elif [ -d "/usr/local/lsws" ]; then
				mv /usr/local/lsws /usr/local/lsws.before.1h >> ${check_log} 2>&1
			fi
		fi

		# Make sure to link /usr/local/lsws to the real directory where litespeed is installed if /usr/local/lsws is not found on this machine
		if [ ! -d "/usr/local/lsws" ] && [ ! -h "/usr/local/lsws" ]; then
			ln -s $webserver_coredir /usr/local/lsws >> ${check_log} 2>&1
		fi

		use_apache=$(grep '</loadApacheConf>' $webserver_conf | sed 's/.*>\(.*\)<.*/\1/g')
		apache_conf='none'
		if [ "$use_apache" == "1" ]; then
			apache_conf=$(grep apacheConfFile $webserver_conf | sed 's/.*>\(.*\)<.*/\1/g')
		fi
	elif [[ "$webserver_bin_basename" =~ ^httpd.* ]] || [[ "$webserver_bin_basename" =~ ^apache.* ]]; then
		webserver_type='apache'
		webserver_coredir=$($webserver_bin_path -V | awk -F \" '/HTTPD_ROOT/{print $2}')
		ap=($($webserver_bin_path -V|grep 'Server ver'|sed 's/.*\/\([0-9]\)\.\([0-9]\).*/\1 \2/'))
	
		if [ "${ap[0]}" == '1' ]; then
			# It is apache 1.3.x
			webserver_version="1.3"
		else
			# it is not Apache 1.3, we assume it is 2.x
			if [ "${ap[1]}" == '0' ]; then
				# It is apache 2.0
				webserver_version="2.0"
			elif [ "${ap[1]}" == '2' ]; then
				# It is apache 2.2
				webserver_version="2.2"
			elif [ "${ap[1]}" == '4' ]; then
				# It is apache 2.2
				webserver_version="2.4"
			fi
		fi

		webserver_conf=$($webserver_bin_path -V | awk -F \" '/SERVER_CONFIG_FILE/{print $2}')
		webserver_conf="$webserver_coredir/$webserver_conf"
		use_apache=1
		apache_conf=$webserver_conf
	fi
}

function check_for_webserver {
	#web_conf_storage='/etc/1h_web_detect.conf'
	show_info "Checking for available" "web server"

	# Is there a web server running on this machine?
	# We only care about the "main" web server which is bound on port 80
	webserver_pid=$(netstat -np --extend --listening | awk '/:80/{print $9}' | awk -F \/ '{print $1}' | head -n 1)

	if [ -z "$webserver_pid" ]; then
		# If there is no active web server we try to bruteforce location to known binaries
		#echo "Web server pid not found. Bruteforcing now."
		webserver_bin_path=$(bruteforce_web_bin)
	else
		#echo "Web server pid found. Reading link"
		webserver_bin_path=$(readlink /proc/$webserver_pid/exe 2>/dev/null | awk '{print $1}')
		if [ -z "$webserver_bin_path" ]; then
			webserver_bin_path=$(bruteforce_web_bin)
		fi
	fi
	
	if [ -z "$webserver_bin_path" ]; then
		# If there was no web server running on port 80 nor we were able to discover known web server binaries via bruteforce
		show_error "No web servers" "No suitable web servers has been found running or not on this machine. Please install apache/litespeed first and try again."
	fi
	
	# Get the base (short) name of the web server binary by stripping path from the variable
	webserver_bin_basename=$(basename $webserver_bin_path)

	# Try to identify the web server and its config files locations based on the binary name
	identify_web_server_type "$webserver_bin_basename"

	# If we can not identify the service that holds port 80 at this moment we will fall back to bruteforce again
	if [ -z "$webserver_type" ] && [ ! -z "$webserver_pid" ]; then
		#echo "Web server on port 80 can not be identified. Bruteforcing now"
		# In certain cases there might be a service that listen on port 80 which is not apache nor litespeed (nginx, varnish are such examples)
		# In those cases there is a big chance the services on port 80 to act as proxies only and apache/litespeed to be running on different ports
		# If we are still unable to identify $webserver_type by this point we will attempt to run bruteforce against known bin paths for known web server binaries
		webserver_bin_path=$(bruteforce_web_bin)
		webserver_bin_basename=$(basename $webserver_bin_path)
		identify_web_server_type "$webserver_bin_basename"
		if [ -z "$webserver_type" ]; then
			# Well there is nothing that can be done at this point. The service on port 80 is unknown to us.
			show_error "Failed to detect" "compatible web server installed on this machine. There is a service (pid $webserver_pid, cmd $webserver_bin_basename) that listens on port 80 but it is not supported by our system ... yet. Please send us report about that. We will appreciate your co-operation."
		fi
	elif [ -z "$webserver_type" ]; then
		# If there is no web server running on port 80 nor we were able to discover known web server binaries ... bail out.
		show_error "Failed to detect" "compatible web server installed on this machine. There are no web servers running on port 80 and we were unable to locate any compatible web server installed on this machine. If you have a web server installed on this machine kindly send us report about that. We will appreciate your co-operation."
	fi

	# Guess the web server init script here
	webserver_init=''
	webserver_inits=''
	if [ "$webserver_type" == 'litespeed' ]; then
		# httpd init script may also control lsws in certain cases. however if the server is running litespeed lsws will be present in 99.9 of the cases
		webserver_inits='lsws httpd'
	elif [ "$webserver_type" == 'apache' ]; then
		webserver_inits='httpd http apache apache2'
	fi

	init_dir='/etc/init.d'
	for init in $webserver_inits; do
		if [ ! -x "$init_dir/$init" ]; then
			continue
		fi
		webserver_init="$init_dir/$init"
		break
	done
	
	if [ -z "$webserver_conf" ]; then
		show_error "$webserver_type missing config" "$webserver_type detected and installed at $webserver_coredir but we were unable to find valid configuration file for this server"
	fi
	
	if [ ! -f "$webserver_conf" ]; then
		show_error "$webserver_type broken config" "$webserver_type detected and installed at $webserver_coredir. Its config was detected at $webserver_conf but such file does not exist"
	fi
	
	if [ "$webserver_type" == 'litespeed' ]; then
		show_info "$webserver_type WEB server detected" "Version: $webserver_version Config: $webserver_conf Init: $webserver_init Use apache conf: $use_apache Apache conf: $apache_conf"
	else
		show_info "$webserver_type WEB server detected" "Version: $webserver_version Config: $webserver_conf Init: $webserver_init"
	fi

	# At the end generate configuration file which will store the web server configuration for this machine
	# This config later can be used by the other scripts part of the 1h systems
	# As the vars in that config will be later read/included by bash scripts we will quote the values in single quotes just in case
	# The first echo should ALWAYS truncate $web_conf_storage
	#echo "webserver_type='$webserver_type'" > $web_conf_storage
	# Rest of the echos should append
	#echo "webserver_version='$webserver_version'" >> $web_conf_storage
	#echo "webserver_conf='$webserver_conf'" >> $web_conf_storage
	#echo "webserver_init='$webserver_init'" >> $web_conf_storage
	#echo "webserver_coredir='$webserver_coredir'" >> $web_conf_storage
	#echo "webserver_bin_path='$webserver_bin_path'" >> $web_conf_storage
	#echo "webserver_bin_basename='$webserver_bin_basename'" >> $web_conf_storage
	#echo "# Use the vars below for litespeed only even we fill them for apache as well" >> $web_conf_storage
	#echo "use_apache='$use_apache'" >> $web_conf_storage
	#echo "apache_conf='$apache_conf'" >> $web_conf_storage
}

function pre_psql_conn_check {
	if [ "${distro}" == 'debian' ]; then
		PGDATA='/var/lib/postgresql/8.4/main'
	else
		PGDATA='/var/lib/pgsql/data'
	fi

	if [ ! -f "$PGDATA/PG_VERSION" ] || [ ! -d "$PGDATA/base" ]; then
		show_info "PostgreSQL database" "Not not initialized yet ... trying to initialize it"

		if [ ! -z "$psql_pkg_suffix" ]; then
			if [ -f /usr/share/pgsql/conversion_create.sql ]; then
				show_warning "PostgreSQL install" "JOHAB Hack required"
				if ( ! sed -i '/JOHAB --> UTF8/,//D' /usr/share/pgsql/conversion_create.sql >> ${check_log} 2>&1 ); then
					show_error "PostgreSQL install" "JOHAB Hack FAILED"
				else
					show_info "PostgreSQL install" "JOHAB Hack PASSED"
				fi
			fi
		fi

		if ( ! /etc/init.d/postgresql initdb >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL database" "/etc/init.d/postgresql initdb FAILED"
		else
			show_info "PostgreSQL database" "/etc/init.d/postgresql initdb PASSED"
		fi
	fi

	if ( ! pgrep 'postgres' >> ${check_log} 2>&1 ); then
		show_warning "PostgreSQL status" "currently down ... trying to start it"
		if ( ! /etc/init.d/postgresql start >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL restart" "FAILED"
		else
			show_info "PostgreSQL restart" "PASSED"
		fi
	else
		show_info "PostgreSQL status" "currently up ... attempting connection"
	fi

	sleep 5
}

function psql_auth_enable {
	pg_hba=$(get_pghba_conf)
	psql_init=$(get_psql_init)

	show_info "PostgreSQL temp ident" "check"
	if ( grep '1H IDENT START' "${pg_hba}" >> ${check_log} 2>&1 ); then
		show_info "PostgreSQL temp ident" "already enabled"
		return 1
	else
		show_info "PostgreSQL ident" "not enabled"
	fi

	show_info "Adding" "PostgreSQL temp ident authentication"
	if ( psql --version | grep ' 8.[12].*' > /dev/null ); then
		auth_conf="# 1H IDENT START\nlocal\tall\tpostgres\tident sameuser\nhost\tall\tpostgres\t127.0.0.1\t255.255.255.255\tident sameuser\n# 1H IDENT END"
	else
		auth_conf="# 1H IDENT START\nlocal\tall\tpostgres\tident\nhost\tall\tpostgres\t127.0.0.1\t255.255.255.255\tident\n# 1H IDENT END"
	fi

	# If a given file has 0 lines in it sed can't find which is the first line of the file and it can NOT add what it has been asked to add to that file.
	# In our case we always want our ident authentication lines to be added at the beginning of the file.
	# To overcome this always add single blank space at the end of the pg_hba.conf file
	echo "" >> "${pg_hba}" 2>/dev/null

	if ( ! sed -i "1i$auth_conf" "${pg_hba}" >> ${check_log} 2>&1 ); then
		show_error "Adding" "PostgreSQL temp ident authentication FAILED"
	else
		show_info "Adding" "PostgreSQL temp ident authentication PASSED"
	fi

	show_info "PostgreSQL reload" "in progress"
	if ( ! $psql_init reload >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL reload" "FAILED"
	else
		show_info "PostgreSQL reload" "PASSED"
	fi

	sleep 5
}

function psql_auth_disable {
    pg_hba=$(get_pghba_conf)
    psql_init=$(get_psql_init)

	show_info "PostgreSQL temp ident" "check"
	if ( ! grep '1H IDENT START' "${pg_hba}" >> ${check_log} 2>&1 ); then
		show_info "PostgreSQL temp ident" "already removed"
		return 1
	else
		show_info "PostgreSQL temp ident" "still enabled"
	fi

	show_info "Removing" "PostgreSQL temp ident authentication"
	if ( ! sed -i '/1H IDENT START/,/1H IDENT END/D' "${pg_hba}" >> ${check_log} 2>&1 ); then
		show_error "Removing" "PostgreSQL temp ident auth FAILED"
	else
		show_info "Removing" "PostgreSQL temp ident auth PASSED"
	fi

	show_info "PostgreSQL reload" "in progress"
	if ( ! $psql_init reload >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL reload" "FAILED"
	else
		show_info "PostgreSQL reload" "PASSED"
	fi

	sleep 5
}

function check_psql_conn {
	if ( ! su - postgres -c "if ( ! psql -Upostgres template1 -c 'select 1+1;' ); then exit 1; fi" >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL connection" "Failed to connect to the psql database. Make sure that the ident authentication for user postgres is enabled"
	else
		show_info "PostgreSQL connection" "PASSED"
	fi
}

function check_psql {
	psql=$(which psql 2>> ${check_log})
	if [ -z "$psql" ]; then
		show_warning "PostgreSQL Version" "PostgreSQL server will be installed on this machine."
		return 0
	fi

	psql_version=$($psql -V | grep PostgreSQL | awk '{print $3}' | awk -F . '{print $1, $2, $3}')
	major=$(echo $psql_version | awk '{print $1}')
	minor=$(echo $psql_version | awk '{print $2}')
	last=$(echo $psql_version | awk '{print $3}')

	if [ "$major" -lt 8 ]; then
		show_warning "PostgreSQL Version" "Outdated. Automated PostgreSQL upgrade will be attempted."
		return 1
	elif [ "$major" -eq 8 ] && [ "$minor" -lt 3 ]; then
		show_warning "PostgreSQL Version" "Outdated. Automated PostgreSQL upgrade will be attempted."
		return 1
	elif [ "$major" -eq 8 ] && [ "$last" -lt 3 ]; then
		show_warning "PostgreSQL Version" "Outdated. Automated PostgreSQL upgrade will be attempted."
		return 1
	elif [ "$minor" -lt 4 ] || [ "$last" -lt 4 ]; then
		show_warning "PostgreSQL Version" "Outdated. Automated PostgreSQL upgrade will be attempted."
		return 1
	else
		show_info "PostgreSQL Version" "PASSED"
		return 2
	fi
}

function check_cpanel {
	show_info "Checking for installed" "control panels"
	if [ -f '/usr/local/cpanel/cpanel' ]; then
		show_info "cPanel" "found"
		control_panel='cpanel'
	elif [ -x '/etc/init.d/directadmin' ]; then
		show_info "DirectAdmin" "found"
		control_panel='da'
	elif [ -x '/etc/init.d/psa' ]; then
		show_info "Plesk" "found"
		#show_error "Plesk" "is not officially supported yet. If you want to try it out, please contact us and we will be happy to assist you."
		control_panel='plesk'
	else
		show_info "No control panels" "installed on this server."
	fi

	if [ "$install_pkg" == 'digits' ] && [ "$control_panel" != 'cpanel' ]; then
		show_error "Digits" "can not be installed on this server. It can be installed on cPanel servers only but cPanel was not found on this machine."
	fi
}

function check_utils {
	show_info "Checking for required" "system tools"
	utils='rpm yum perl wget curl grep openssl sed iptables chkconfig sed touch awk sendmail ip ifconfig lsattr ls chattr touch file sysctl stat chmod chown readlink netstat rsync'
	for util in $utils; do
		if [ "${distro}" == 'debian' ]; then
			if [[ "${util}" =~ rpm|yum|chkconfig ]]; then
				continue
			fi
			try_install_cmd="apt-get -o Dpkg::Options::=--force-confold -y install $util"
		else
			try_install_cmd="yum -y install $util"
		fi

		#show_info "Checking for" "$util"
		results=$(which $util 2>> ${check_log})
		if [ -z "$results" ]; then
			show_error "$util" "Not found. Please install '$util' first and re-run the installer. You can try with: $try_install_cmd"
		fi
	done
	show_info "System tools check" "PASSED"
}

function fix_file_permissions {
	file_path="$1"
	file_perms="$2"

	if ( ! chmod "$file_perms" "$file_path" >> $check_log 2>&1 ); then
		show_error "$file_path permissions fix failed" "Failed to change $file_path permissions to $file_perms"
	fi

	show_info "$file_path permissions fixed" "Successfully applied $file_perms to $file_path"
}

function check_perl_executable {
	perl_perms=$(stat -c '%a' -t -L "$perl_path")
	if [ -z "$perl_perms" ]; then
		return
	fi

	if [ "$perl_perms" != '755' ] && [ "$perl_perms" != '711' ] && [ "$perl_perms" != '555' ]; then
		show_warning "Incorrect $perl_path permissions" "Current file permissions are $perl_perms. 1H software need 755. This will be automatically fixed during installation."
		fix_perl_perms=1
	fi
}

function check_max_pids {
	max_pid=$(sysctl -a 2>/dev/null | awk '/kernel.pid_max/{print $3}')

	if [ -z "$max_pid" ]; then
		# Go back if the value is empty
		return
	fi

	if [ "$max_pid" -gt $max_pid_limit ]; then
		show_warning "High kernel.pid_max" "sysctl value for kernel.pid_max is currently set to $max_pid. Hive/Guardian need kernel.pid_max set to at most $normal_pid_limit. This will be automatically adjusted during the installation."
		adjust_max_pid=1
	fi
}

function cpanel_statsfs_check {
	if [ -f $statfs_conf ]; then
		return
	fi

	show_warning "cPanel statfs" "will be disabled on this server. File $statfs_conf will be automatically created."
	disable_statfs=1
}

function disableStatfs {
	if [ -f $statfs_conf ]; then
		return
	fi

	show_info "Currently disabling" "cPanel statfs"
	touch $statfs_conf >> ${check_log} 2>&1
	show_info "cPanel statfs" "disabled as expected"
}

function check_shmmax_sysctl {
	shmmax=$(sysctl -a 2>/dev/null | awk '/kernel.shmmax/{print $3}')

	if [ -z "$shmmax" ]; then
		return
	fi

	if [ "$shmmax" -lt $required_shmmax ]; then
		show_warning "Low kernel.shmmax" "sysctl value for kernel.shmmax is currently set to $shmmax. PostgreSQL requires kernel.shmmax set to at least $required_shmmax. This will be automatically adjusted during the installation."
		adjust_shmmax=1
	fi
}

function change_sysctl {
	sysctl_key="$1"
	sysctl_value="$2"
	if ( ! sysctl -w $sysctl_key=$sysctl_value >> ${check_log} 2>&1 ); then
		show_error "$sysctl_key fix failed" "Failed to set $sysctl_key to $sysctl_value"
	fi
}

function unlock_sysctl_conf {
	chattr -ai "$sysctl_conf" >> ${check_log} 2>&1
}

function remove_old_sysctl_setting {
	sysctl_key="$1"
	sed -i "/^\s*$sysctl_key/D" "$sysctl_conf" >> ${check_log} 2>&1
}

function apply_new_sysctl_conf {
	sysctl_key="$1"
	sysctl_value="$2"
	echo "$sysctl_key = $sysctl_value" >> "$sysctl_conf" 
}

function change_sysctl_conf {
	sysctl_key="$1"
	sysctl_value="$2"
	if [ -f $sysctl_conf ]; then
		unlock_sysctl_conf
		remove_old_sysctl_setting "$sysctl_key"
	fi
	apply_new_sysctl_conf "$sysctl_key" "$sysctl_value"
}

function check_plesk_version {
	plesk_version_file='/usr/local/psa/version'
	if [ ! -f $plesk_version_file ]; then
		show_error "Plesk version" "Failed to determine current running version of Plesk. $plesk_version_file is missing"
	fi
	plesk_version=$(awk '{print $1}' /usr/local/psa/version)
	echo ${plesk_version} | awk -F . '{print $1, $2, $3}' | while read major minor last; do
		if [ "$major" -lt 9 ]; then
			exit 1
		fi
		if [ "$major" -eq 9 ] && [ $minor -lt 5 ]; then
			exit 1
		fi
		if [ "$major" -eq 9 ] && [ $last -lt 4 ]; then
			exit 1
		fi
	done
	# while read spawns a subshell so we should check the exit status of the subshell
	if [ $? -ne 0 ]; then
		show_error "Plesk version" "Failed. Found version $plesk_version while we require at least 9.5.4"
	fi

	show_info "Plesk version" "$plesk_version ... PASSED"
}

function cpanel_ulimits_check {
	for ulimit_file in $ulimit_files; do
		if [ ! -f "$ulimit_file" ]; then
			continue
		fi
		# Check if known fork bomb protection pattern match is found in $ulimit_file
		if ( grep '"$LIMITUSER" != "root"' $ulimit_file >> ${check_log} 2>&1 ); then
			# Before instructing installer to patch $ulimit_file ulimits protection file please ensure that mysql and postgres are not excluded already
			if ( grep 'LIMITUSER.*mysql' $ulimit_file >> ${check_log} 2>&1 ) && ( grep 'LIMITUSER.*postgres' $ulimit_file >> ${check_log} 2>&1 ); then
				continue
			fi
			show_warning "cPanel Shell Fork Bomb Protection" "Currently enabled. It will be disabled for users 'mysql' and 'postgres' to prevent databases out of memory errors."
			ulimit_fix=1
		fi
		return
	done
}

function cpanel_ulimits_fix {
	for ulimit_file in $ulimit_files; do
		if [ ! -f "$ulimit_file" ]; then
			continue
		fi
		if ( ! grep '"$LIMITUSER" != "root"' $ulimit_file >> ${check_log} 2>&1 ); then
			continue
		fi
		# Go ahead and extend the if statement on lines like this one:
		#	if [ "$LIMITUSER" != "root" ]; then
		# New extended line will then looks like
		#	if [ "$LIMITUSER" != "root" ] && [ "$LIMITUSER" != "postgres" ] && [ "$LIMITUSER" != "mysql" ]; then
		# This will ensure that the ulimits applied to the mysql and postgres users will be just the same as those applied to the root user
		show_info "Patching" "cPanel Shell Fork Bomb Protection in $ulimit_file"
		if ( ! sed -i '/LIMITUSER.*root/s/]/] \&\& [ "$LIMITUSER" != "postgres" ] \&\& [ "$LIMITUSER" != "mysql" ]/g' $ulimit_file ); then
			show_error "Failed to exclude" "'postgre' and 'mysql' users from cPanel Shell Fork Bomb Protections defined in $ulimit_file"
		fi
		show_info "$ulimit_file" "successfully patched"
	done
}

function check_acls {
	acl_test_file='/home/acl.test.1h'
	if ( ! touch $acl_test_file >> $check_log 2>&1 ); then
		return 0
	fi

	show_info "Testing for" "Linux Extended ACL support"
	if ( ! setfacl -m u:nobody:r $acl_test_file >> $check_log 2>&1 ); then
		# setfacl failed which means that most probbably acls are not enabled on this partition
		show_warning "Linux Extended ACL support" "We will attempt to automatically enable it for /home partition during installation."
		rm -f $acl_test_file
		return 0
	else
		show_info "Linux Extended ACL support" "PASSED"
		rm -f $acl_test_file
		return 1
	fi
}

function check_perl_modules {
	install_cnt=0
	if [ "$1" == "standard" ]; then
		required_modules="File::Basename DBI DBD::Pg JSON::XS DBD::mysql Spreadsheet::WriteExcel PDF::Create IO::Socket::INET CGI CGI::Carp Bundle::LWP LWP::UserAgent File::Copy"
	elif [ "$1" == "gearman" ]; then
		required_modules="Gearman::Client Gearman::Worker Gearman::XS::Worker"
	fi

	for module in $required_modules; do
		if ( ! perl -M$module -e 1 >> ${check_log} 2>&1 ); then
			show_warning "Perl module $module" "TO BE INSTALLED"
			let install_cnt=$install_cnt+1
		else
			show_info "Perl module $module" "PASSED"
		fi
	done
	return $install_cnt
}

function check_puppetd {
	show_info "Checking for" "puppetd"
	if [ ! -x /etc/init.d/puppetd ]; then
		show_info "puppetd not found" "Good. Check PASSED."
		return
	fi
	if ( ! /etc/init.d/puppetd status | grep "is running" >> $check_log 2>&1 ); then
		# pupped found but it is NOT running. that is ok.
		show_info "puppetd not running" "Good pupped found but NOT running. Check PASSED."
		return
	fi
	# If we reach this code this mean that puppetd is running and we should quit
	show_error "puppetd is running" "Check FAILED.
	Please stop puppetd before proceeding with the installation. You can stop the Puppetmaster daemon by executing:
		/etc/init.d/pupped stop
	Also make sure that puppetd will not erase the following repositories once it is started:
		/etc/yum.repos.d/1h.repo
		/etc/yum.repos.d/epel.repo
		/etc/yum.repos.d/epel-testing.repo"
}

function check_mpm_type {
	# This check applies to Apache 2.0, 2.2, 2.4 only
	if [ "$webserver_type" == 'litespeed' ] || [ "$webserver_version" == '1.3' ]; then
		return
	fi

	show_info "Checking current MPM type" "for Apache $webserver_version"

	mpm_type=$($webserver_bin_path -V 2>> ${check_log} | awk -F \" '/APACHE_MPM_DIR/{print $2}')

	if [ "$webserver_version" == '2.4' ]; then
		mpm_type=$($webserver_bin_path -V 2>> ${check_log} | awk '/^Server MPM/{print $3}')
	fi

	if [ -z "$mpm_type" ]; then
		show_error "Blank MPM" "Failed to detect current MPM type for Apache $webserver_version"
	fi
	
	if [[ "$mpm_type" =~ 'worker' ]]; then
		show_error "MPM Worker Found" "Apache MPM Worker is not supported by Hive yet. Installation can not continue. Please convert Apache MPM to Prefork and try again."
	elif [[ "$mpm_type" =~ 'prefork' ]]; then
		show_info "MPM Prefork found" "PASSED"
	else
		show_error "Unknown MPM" "Apache $webserver_version MPM $mpm_type is not supported by Hive yet. Installation can not continue. Please convert Apache MPM to Prefork and try again."
	fi
}

function scan_apache_modules {
	mod_php=0
	mod_suphp=0
	mod_disable_suexec=0
	fcgid_module=0

	# Get the list of the apache core config as well as all files that are included
	all_web_config_files="$webserver_conf $(grep -i '^\s*Include' $webserver_conf | sed -e 's/"//g' -e "s/'//g" | awk '{print $2}')"

	for current_config in $all_web_config_files; do
		# Transform relative config paths to full paths if needed
		if ( ! echo $current_config | grep '^\/' > /dev/null  ); then
			server_root=$(grep -i '^\s*ServerRoot' $webserver_conf | awk '{print $2}')
			current_config="$server_root/$current_config"
		fi
		# Move ahead if there is no such file
		if [ ! -f $current_config ]; then
			continue
		fi

		# Check for mod_php
		if ( grep 'libphp' $current_config | grep -v '^\s*#' >> ${check_log} 2>&1 ); then
			mod_php=1
		fi
		# Check for mod_suPHP
		if ( grep 'suPHP_Engine on' $current_config >> ${check_log} 2>&1 ); then
			mod_suphp=1
		fi
		# Check for mod_disable_suexec
		if ( grep 'mod_disable_suexec' $current_config | grep -v \\# | grep 'LoadModule' >> ${check_log} 2>&1 ); then
			mod_disable_suexec=1
		fi
		# Check for mod_fastcgi
		if ( grep 'fcgid_module' $current_config | grep \\# >> ${check_log} 2>&1 ); then
			fcgid_module=1
		fi
	done

	if [ "$fcgid_module" == "1" ]; then
		show_error "FCGI" "Fast-CGI installation found on the server. Please contact 1H support prior to proceeding."
	else
		show_info "FCGI" "PASSED"
	fi

	if [ "$mod_disable_suexec" == "1" ]; then
		show_warning "mod_disable_suexec" "mod_disable_suexec will be entirely disabled on this machine"
	else
		show_info "mod_disable_suexec" "PASSED"
	fi

	if [ "$mod_suphp"  == "1" ]; then
		show_warning "mod_suphp" "mod_suphp will be disabled on this machine and will be replaced with mod_hive."
		#mkdir -p /var/lock/
		#touch /var/lock/mod_suphp_to_suexec >> ${check_log} 2>&1
		#chattr +ai /var/lock/mod_suphp_to_suexec >> ${check_log} 2>&1
	else
		show_info "mod_suphp" "PASSED"
	fi

	if [ "$mod_php" == "1" ]; then
		show_info "mod_php" "FOUND ... conversion needed!"
		if [ ! -f "$auto_agreement" ]; then
			echo -e "${RED} !!! WARNING !!! !!! WARNING !!! !!! WARNING !!! ${RESET}"
			echo -e "${BOLD}
1H Hive heavily relies on its modified SuExec technology in order to bring you the CPU Statistics and guarantee security and stability of your servers. Since this server is currently NOT running PHP in SuExec mode but mod_php instead, a few configuration and permission changes have to be made in order for 1H Hive to start working. The changes 1H Hive will impose are the following, please make sure to read and understand them prior to installing:"
			echo -e "${BOLD}
-> 1H mod_hive and SuExec will be included in current Apache configuration;
-> Current mod_php will be disabled;
-> All user accounts' folders and files with permissions above 755 (eg. 777) will be set to 755;
-> All user .htaccess PHP flags will be commented and the commented flags will be put in separate php.ini files into the user folder. 
${RESET}"
			echo -e "${RED} !!! WARNING !!! !!! WARNING !!! !!! WARNING !!! ${RESET}"
			echo -e "${BOLD}
Changing the permissions of user files and folders, as well as commenting lines in .htaccess and putting them into php.ini files is an I/O and time consuming process. During this change some of the user accounts on the server might not function properly.

If you are unsure what this means, please contact 1H Support Team prior to completing the installation process! In case you proceed with the installation and face any problems after that, please immediately contact the 1H Support Team by posting a support request via the 1H client area - Support section. 
${RESET}"
			echo -e -n "${BOLD} Type in [I agree] without the quotes to agree to this disclaimer.
 Type in [stop] without the quotes if you don't agree.
 Your answer is: ${RESET}"
			read y
			if ( ! echo "$y" | grep -i 'I\s*agree' > /dev/null ); then
				show_error "Installations" "Canceled by user"
			fi
		fi
		mkdir -p /var/lock/
		touch /var/lock/mod_php_to_suexec >> ${check_log} 2>&1
		chattr +ai /var/lock/mod_php_to_suexec >> ${check_log} 2>&1
	fi
}

function check_nss_ldap {
	if ( rpm -qa | grep -E "^nss_ldap|^nss-pam-ldapd" >> ${check_log} 2>&1 ); then
		show_warning "nss_ldap" "1H Software requires nss_ldap to be removed."
		return 0
	else
		show_info "nss_ldap" "PASSED"
		return 1
	fi
}

function check_nscd {
	if [ -x /usr/sbin/nscd ]; then
		if ( ! /usr/sbin/nscd -V | grep 'nscd which does not hang' >> ${check_log} 2>&1 ); then
			show_warning "nscd" "nscd will be replaced with customized and improved unscd"
			return 0
		else
			show_info "nscd" "PASSED"
			return 1
		fi
	else
		show_warning "nscd" "unscd will be installed on the server"
		return 0
	fi
}

function crond_changes {
	show_warning "Crond" "cron daemon will be replaced with custom chrooted one"
}

function check_gearman {
	if [ ! -x /usr/sbin/gearmand ]; then
		show_warning "gearmand" "gearmand will be installed on the server"
		return 0
	else
		show_info "gearmand" "PASSED"
		return 1
	fi
}

function check_homematch {
	# We skip this check if the file is not there
	if [ ! -f /etc/wwwacct.conf ]; then
		return 1
	fi
	home_match=$(awk '/HOMEMATCH/{print $2}' /etc/wwwacct.conf)
	if [[ "$home_match" =~ home ]]; then
		show_warning "cPanel HOMEMATCH" "$home_match will be erased from /etc/wwwacct.conf"
		return 0
	fi
	return 1
}

function check_quota {
	quotacnt=0
	acct_storage=''
	if [ -f /etc/wwwacct.conf ]; then
		acct_storage=$(awk '/HOMEDIR/{print $2}' /etc/wwwacct.conf)
	fi
	if [ -z $acct_storage ]; then
		# If acct_storage is zero (no wwwacct.conf or wwwacct.conf contains no valid HOMEDIR) we accept that the storage is at /home
		acct_storage='/home'
	fi
	for storage in $acct_storage; do
		partition=$(df -h -P $storage | grep -v Mounted | awk '{print $6}')
		if [ -x /sbin/quotaon ]; then
			if ( ! /sbin/quotaon -p $partition 2>>${check_log} | grep user | grep 'is on' >> ${check_log} 2>&1 ); then
				show_warning "Quota on $partition" "Quota is disabled on $partition. It will be automatically enabled. This might cause high I/O on your hard drives and increase overall server load during the initialization process."
				let quotacnt=$quotacnt+1
			else
				show_info "Quota on $partition" "PASSED"
			fi
		fi
	done
	return $quotacnt
}

function check_core {
	show_info "Currently running check" "core"
	check_arch
	check_os
	# Find the server control panel prior we check for the current installed and active web server
	check_cpanel
	check_utils
	check_for_webserver

	# If we have plesk on this server we should verify its version as well
	if [ "$control_panel" == 'plesk' ]; then
		check_plesk_version
	elif [ "$control_panel" == 'cpanel' ]; then
		cpanel_ulimits_check
	fi

	# The acls are no longer used so we skip this check
	#check_acls
	check_public_ip

	if [ "${distro}" != 'debian' ]; then
		check_mysql_devel
	fi

	check_perl_modules "standard"
	check_puppetd

	# Make sure to check if any cron daemon is installed if we are not installing hive or all
	# Hive/all will install their own cron so there is no need to check there
	if [ "$install_pkg" != 'hive' ] && [ "$install_pkg" != 'all' ]; then
		crond_check
	fi

	# Check if we shoulld stop guardian only if the package we are currently installing is NOT guardian
	if [ "$install_pkg" != 'guardian' ]; then
		check_for_guardian
	fi

	# check if shmmax is set to at least $required_shmmax which is required by PostgreSQL
	# This should be performed during all type of installs as PSQL is a must for all sw packages
	check_shmmax_sysctl

	# Make sure that perl is executable by group and others
	# If incorrect permissions are detected automatic fix will be applied at later stage
	check_perl_executable

	return 1
}

function check_rpm_apache {
	# For cPanel and DirectAdmin servers rpm based httpd installations should be removed
	if ( rpm -qa | grep ^httpd-[1-2].* >> ${check_log} 2>&1 ); then
		show_warning "RPM httpd installation" "Found ... it will be removed"
		remove_rpm_httpd=1
	else
		show_info "RPM httpd installation" "PASSED"
	fi
}

function check_mysql_devel {
	if ( ! rpm -qa | grep -iE "^mysql-devel|MariaDB-devel|Percona-Server-devel|MySQL5(\\.?[0-9])*-devel|betterlinux-mysql-devel|betterlinux-cpanel-mysql-devel" >> ${check_log} 2>&1 ); then
		show_warning "MySQL-devel" "Not Found ... Automated install will be attempted."
		install_mysql_devel=1
	else
		show_info "MySQL-devel" "PASSED"
	fi
}

function install_mysql_devel {
	show_info "Installing MySQL-devel" "Needed for DBD::mysql"
	if ( ! yum -y install MySQL-devel mysql-devel >> ${check_log} 2>&1 ); then
		show_error "MySQL-devel install"  "FAILED"
	else
		show_info "MySQL-devel install" "PASSED"
	fi
}

function check_license {
	# For script based installations do not care about licenses.
	if [ -f "${auto_agreement}" ]; then
		return
	fi

	swId="$1"
	swName="$2"

	license_response=$(curl -s -d request="[\"isLicensed\",{\"product_type\":\"$swId\"}]" $client_api 2>/dev/null | sed -e 's/\[//g' -e 's/\]//g')
	echo "LICENSE RESPONSE: $license_response" >> ${check_log} 2>&1

	if [ -z "$license_response" ]; then
		show_error "$swName license" "Failed to fetch from master server. Try again later."
	elif [[ "$license_response" =~ 'Missing license information' ]]; then
		show_error "$swName license" "Not available.\n\to Please login into your 1H user are at https://www.1h.com/login to activate your license first"
	elif [[ "$license_response" =~ licensed.*true ]]; then
		show_info "$swName license" "PASSED"
	else
		show_error "$swName license" "Unknown response from master server. Try again later."
	fi

	return 1
}

function check_public_ip {
	# This function checks if the server has at least one public accessible IP which is _not_ part of the network ranges described here
	# http://en.wikipedia.org/wiki/Private_network
	# 1H software requires at least one public accessible IP to be available on the server so it can function properly
	server_ip=$(ip -4 -oneline addr list | sed 's/\/[0-9]\{1,2\}//' | awk '{print $4}' | awk -F . '{if (($1 >= 1 && $1 <=255 && $1 != 10) &&
	($2 >= 0 && $2 <= 255) &&
	($3 >= 0 && $3 <= 255) &&
	($4 >= 1 && $4 <= 254) &&
	! ($1 == 192 && $2 == 168) &&
	! ($1 == 172 && ($2 >=16 || $2 <=32)) &&
	! ($1 == 10) &&
	! ($1 == 127 && $2 == 0 && $3 == 0))
	{print $0}}' | head -n1)

	# If $server_ip is zero we did not obtained any public ips so we should quit
	if [ -z "$server_ip" ]; then
		show_error "Public IP not available" "Failed to obtain at least one public accessible IP on this machine. In order for 1H software to function properly the machine should have at least one IP address which is not in a private network range."
	fi
}

function check_diskspace {
	root=($(df -P / | grep -v -i system))
	if [ ! -z ${root[3]} ] && [ ${root[3]} -lt 1000000 ]; then
		show_error "Diskspace" "not enough free space on /"
	fi
}

function crond_check {
	if [ "${distro}" != 'debian' ]; then
		cron_results=$(which crond 2>> ${check_log})
	else
		cron_results=$(which cron 2>> ${check_log})
	fi
	show_info "checking for" "cron daemon"
	if [ -z "$cron_results" ]; then
		show_info "cron daemon" "not found"
		show_warning "cron daemon" "will be installed on this server."
		install_crond=1
	else
		show_info "crond daemon" "found"
	fi
}

function doYumCrondInstall {
	show_info "Installing" "vixie-cron"
	if ( ! yum -y --exclude=crond,crond-plesk install vixie-cron >> ${check_log} 2>&1 ); then
		show_error "vixie-cron" "installation failed"
	else
		show_info "vixie-cron" "successfully installed"
	fi
}

function doAptCrondInstall {
	show_info "Installing" "cron"
	if ( ! apt-get -o Dpkg::Options::=--force-confold -y install cron >> ${check_log} 2>&1 ); then
		show_error "cron" "installation failed"
	else
		show_info "cron" "successfully installed"
	fi
}

function doCrondInstall {
	if [ "${distro}" == 'debian' ]; then
		doAptCrondInstall
	else
		doYumCrondInstall
	fi
}

function check_hive {
	show_info "Currently running check" "hive"

	#if [ -z "$control_panel" ]; then
	#	show_warning "Hive" "can not be installed on a server without control panel. We need cPanel/DirectAdmin/Plesk. We will skip Hive installation."
	#	return 1
	#fi

	check_diskspace
	check_mpm_type

	if [ "$control_panel" == 'cpanel' ]; then
		cpanel_statsfs_check
	fi

	if [ "$webserver_type" == 'apache' ]; then
		scan_apache_modules
	fi

	if [ "${distro}" != 'debian' ]; then
		check_nss_ldap
		if [ "$?" == "0" ]; then
			remove_nss_ldap=1
		fi
	fi

	# Test if there is an RPM based httpd installation that we should remove ONLY in case the control panel is DA or cPanel
	# We should NOT do that for Plesk
	# Removal is handled at a later stage
	#if [ "$webserver_type" == 'apache' ] && [ "$control_panel" != "plesk" ] && [ "$webserver_version" == "1.3" ]; then
	#	check_rpm_apache
	#fi

	check_nscd
	crond_changes
	check_homematch
	check_license "1" "hive"

	return 1
}

function getPortalState {
	portal_results=$(curl -s -d request=[\"checkPortal\"] $client_api 2>/dev/null | sed -e 's/\[//g' -e 's/\]//g')
	portalInstalled=0
	if [ -z "$portal_results" ]; then
		show_warning "Portal status" "Empty. We strongly suggest you to try continuing your installation later."
	elif [[ "$portal_results" =~ (Portal not found for this client|Client IP not found in database) ]]; then
		portalInstalled=0
	else
		portalInstalled=1
	fi
	if [ "$1" == "0" ] && [ "$portalInstalled" == "1" ]; then
		# If we install portal we should warn if portal is already installed on another server
		show_warning "1H Portal already installed" "Portal is already installed on another server. Proceed with this installation only in case:\n\to You would like to migrate your old portal to this server\n\to If that is the case make sure to run the following command on all servers with 1H software installed on them afterwards:\n\t\t/usr/local/1h/bin/change_portal.sh"
	#elif [ "$1" == "1" ] && [ "$portalInstalled" == "0" ]; then
	#	# If the client tries to install something else prior installing portal it is better to warn him about that
	#	show_warning "1H Portal not installed" "Portal is not installed on any of your servers.\n\to We strongly advise you to install it first by using:\n\t\t$0 portal\n\to Once you finish with your portal installation you can run this installation again with:\n\t\t$0 $install_pkg\n\to If you still want to continue installing $install_pkg and install portal at a later stage you should re-configure the servers installed prior installing portal by using:\n\t\t/usr/local/1h/bin/change_portal.sh"
	fi
}

function check_portal {
	show_info "Currently running check" "portal"
	check_gearman
	# Gearman::Client and Gearman::Worker are now part of the 1h packed gearman RPM so we do not need this check
	#check_perl_modules "gearman"
	check_license "5" "portal"
	return 1
}

function check_digits {
	show_info "Currently running check" "digits"

	if [ "$control_panel" != 'cpanel' ]; then
		if [ -z "$control_panel" ]; then
			show_warning "Digits" "is not compatible with servers that do not have cPanel installed. It can be installed on cPanel servers only. We will simply skip it's installation."
		else
			show_warning "Digits" "is not compatible with $control_panel. It can be installed on cPanel servers only. We will simply skip it's installation."
		fi
		return 0
	fi

	check_quota
	return 1
}

function check_for_guardian {
	guardian_init_script='/etc/init.d/guardian'
	guard_config='/usr/local/1h/etc/guardian.conf'

	files_to_check="$guardian_init_script $guard_config"
	for file_to_check in $files_to_check; do
		if [ ! -f "$file_to_check" ]; then
			# If one of the required files is missing we should just return from this function
			return
		fi
	done

	pidfile=$(awk -F'=' '/^pidfile\s*=/{print $2}' "$guard_config" 2>/dev/null)
	if [ -z "$pidfile" ] || [ ! -f "$pidfile" ]; then
		# If the pid file is blank (not found in the conf) or it does not exist we should return
		return
	fi

	pid=$(<$pidfile)
	if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
		# If the pid stored in the pid file is not in the propper format we should return
		return
	fi

	if [ ! -d "/proc/$pid" ]; then
		# If the pid stored in the pid file does not exist in proc most probbably guardian is already stopped so we return
		return
	fi

	show_warning "Guardian will be stopped" "In order to avoid any conflicts during the installation Guardian monitoring will be stopped on this server while installation is in progress"
	should_stop_guardian=1
}

function guardian_init {
	if ( ! /etc/init.d/guardian $1 >> ${check_log} 2>&1 ); then
		# To prevent loops in the show_error function we zero should_stop_guardian variable before we call this function
		should_stop_guardian=0
		show_error "Guardian $1" "FAILED"
	fi

	show_info "Guardian $1" "PASSED"
}

function check_guardian {
	show_info "Currently running check" "guardian"
	check_license "2" "guardian"
	return 1
}

function check_hawk {
	show_info "Currently running check" "hawk"
	return 1
}

function doNssLdapErase () {
	for ldap_pkg in nss_ldap nss-pam-ldapd; do
		if ( ! rpm -q "${ldap_pkg}" >> ${check_log} 2>&1 ); then
			continue
		fi
		if ( ! rpm -e --allmatches --nodeps ${ldap_pkg} >> ${check_log} 2>&1 ); then
			show_error "${ldap_pkg} uninstall" "FAILED"
		else
			show_info "${ldap_pkg} uninstall" "PASSED"
		fi
	done
}

function doRepoCheck () {
	if [ "${distro}" == 'debian' ]; then
		repo_url='http://sw.1h.com/debian-testing/amd64/1h-repository_0.0.1-8_all.deb'
		if ( ! grep sw.1h.com /etc/apt/sources.list >> ${check_log} 2>&1 ); then
			show_warning "1H repository" "Not installed ... installing it now"
			if ( ! curl -s "${repo_url}" > /var/cache/apt/archives/1h-repository_0.0.1-8_all.deb 2>> ${check_log} ); then
				show_error "1H repository download" "FAILED. curl ${repo_url} > /var/cache/apt/archives/1h-repository_0.0.1-8_all.deb returned false."
			fi
			if ( ! dpkg -i /var/cache/apt/archives/1h-repository_0.0.1-8_all.deb >> ${check_log} 2>&1 ); then
				show_error "1H repository installation" "FAILED. dpkg -i /var/cache/apt/archives/1h-repository.deb returned false."
			fi
		fi
	else
		if [ ! -f /etc/yum.repos.d/1h.repo ]; then
			show_warning "1H repository" "Not installed ... installing it now"
			if ( ! rpm -Uvh $repo_url >> ${check_log} 2>&1 ); then
				show_error "1H repository installation" "FAILED"
			else
				show_info "1H repository installation" "PASSED"
			fi
		fi
	fi

	show_info "1H repository" "PASSED"
}

function doRepoCache () {
	show_info "Updating yum's cache" "because of the doRepoSwitch request."
	if ( ! yum makecache >> ${check_log} 2>&1 ); then
		show_info "yum makecache" "has some issues. This is not fatal. We will continue anyway."
	else
		show_info "yum makecache" "PASSED"
	fi
}

function doAptGetUpdate () {
	show_info "Updating" "apt-get mirrors."
	if ( ! apt-get update >> ${check_log} 2>&1 ); then
		show_info "apt-get update" "has some issues. This is not fatal. We will continue anyway."
	else
		show_info "apt-get update" "PASSED"
	fi
}

function doRepoSwitch () {
	show_info "Switching to" "1H test repository"
	if [ "${distro}" == 'debian' ]; then
		if ( ! sed -i '/http:\/\/sw.1h.com/s/\/debian\//\/debian-testing\//g' /etc/apt/sources.list >> ${check_log} 2>&1 ); then
			show_error "Switch" "FAILED"
		fi
	else
		if ( ! sed -i '/baseurl/s/centos/testing/g' /etc/yum.repos.d/1h.repo >> ${check_log} 2>&1 ); then
			show_error "Switch" "FAILED"
		fi
		# Make sure to always update the yum cache when we switch the respos
		doRepoCache
	fi

	show_info "Switch" "PASSED"
}

function doUnlockConfigs () {
	for (( i = 0 ; i < ${#configs_to_unlock[@]} ; i++ )); do
		# Skip this if the file is missing
		if [ ! -f "${configs_to_unlock[$i]}" ]; then
			#echo "${configs_to_unlock[$i]} not found. going ahead"
			continue
		fi
	
		config_attribs=$(lsattr "${configs_to_unlock[$i]}" | sed -e 's/-//g' -e 's/ .*//g' -e 's/e//g')
		if [ -z "$config_attribs" ]; then
			#echo "${configs_to_unlock[$i]} has no attribs so we will skip it"
			continue
		fi

		show_info "Locked config" "${configs_to_unlock[$i]} seems to be locked with $config_attribs attributes. Attempting to unlock it ..."
		if ( ! chattr -${config_attribs} "${configs_to_unlock[$i]}" >> ${check_log} 2>&1 ); then
			show_error "Unlocking ${configs_to_unlock[$i]}" "FAILED"
		else
			show_info "Unlocking ${configs_to_unlock[$i]}" "PASSED"
		fi

		configs_to_unlock_attribs[$i]="$config_attribs"
		should_relock_configs=1
	done
}

function changeFastMirrorStatus () {
	# Change the status of the YUM fastest mirror plugin
	# Takes two arguments
	# $1 - The new status we will set for the plugin
	# $2 - The old status of the plugin we expect prior we change the status to $1
	
	# By heaving $1 and $2 we are allowed to use this function for both enable and disable the plugin
	# This saves us from creating another separate function :)

	new_status="$1"
	old_status="$2"

	fastmirror_conf='/etc/yum/pluginconf.d/fastestmirror.conf'

	if [ ! -f "$fastmirror_conf" ]; then
		return
	fi
	
	# Get the status of the fastest mirror plugin here
	fastmirror_status=$(awk -F = '/^[ \t]*enabled/{print $2}' $fastmirror_conf)

	if [ "$fastmirror_status" != "$old_status" ]; then
		# Nothing to do if $fastmirror_status is already disabled
		return
	fi

	sed -i "/enabled/s/$old_status/$new_status/" "$fastmirror_conf" >> ${check_log} 2>&1

	if [ "$new_status" == '0' ]; then
		should_revert_fastmirror=1
	fi
}

function doRelockConfigs () {
	for (( i = 0 ; i < ${#configs_to_unlock[@]} ; i++ )); do
		# Skip this if the file is missing
		if [ ! -f "${configs_to_unlock[$i]}" ]; then
			#echo "${configs_to_unlock[$i]} not found. going ahead"
			continue
		fi
	
		if [ -z "${configs_to_unlock_attribs[$i]}" ]; then
			#echo "${configs_to_unlock[$i]} has no attribs stored in the configs_to_unlock_attribs array so we will skip it"
			continue
		fi
	
		#echo "${configs_to_unlock[$i]} has ${configs_to_unlock_attribs[$i]} attributes. We will revert them"
		show_info "Locked config" "${configs_to_unlock[$i]} was previously locked with ${configs_to_unlock_attribs[$i]} flags. Attempting to re-lock it ..."
		if ( ! chattr +${configs_to_unlock_attribs[$i]} "${configs_to_unlock[$i]}" >> ${check_log} 2>&1 ); then
			# To prevent loops in the show_error function should_relock_configs should be set to 0 before we call it here
			should_relock_configs=0
			show_error "ReLocking ${configs_to_unlock[$i]}" "FAILED"
		else
			show_info "ReLocking ${configs_to_unlock[$i]}" "PASSED"
		fi
	done
}

function doEpelInstall () {
	if ( rpm -q epel-release >> ${check_log} 2>&1 ) && [ -f /etc/yum.repos.d/epel.repo ]; then
		# Consider epel as installed and functional only in case
		# - we find it in the rem -q
		# - the repo config file exists
		# - repo is enabled
		
		# Ensure that the epel main repo is enabled before we return from this function
		# This regex change enabled=.* to enabled=1 ONLY on the first row which has enabled= line
		sed -i '0,/enabled/s/^\s*enabled\s*=.*/enabled=1/' /etc/yum.repos.d/epel.repo
		return 1
	fi

	# Pick-up epel release depending on the OS Major number
	#epel_url='http://download.fedora.redhat.com/pub/epel/5/i386/epel-release-5-4.noarch.rpm'
	#epel_url='http://download.fedoraproject.org/pub/epel/5/i386/epel-release-5-4.noarch.rpm'
	epel_url='http://sw.1h.com/centos/5/epel-release-5-4.noarch.rpm'
	if [ "${os_major}" -eq 6 ]; then
		#epel_url='http://download.fedora.redhat.com/pub/epel/6/i386/epel-release-6-5.noarch.rpm'
		#epel_url='http://mirror.telepoint.bg/fedora/epel/6/i386/epel-release-6-5.noarch.rpm'
		epel_url='http://sw.1h.com/centos/6/epel-release-6-5.noarch.rpm'
	fi

	# If we reach this code epel-release is not found in the rpm -q list or its repo file is missing so we have to reinstall it

	# Try to uninstall epel-release even it is not installed. We do not care about the output/results of this command
	rpm -e --nodeps epel-release >> ${check_log} 2>&1

	show_info "Epel RPM repository" "installation in progress"
	if ( ! rpm -Uvh $epel_url >> ${check_log} 2>&1 ); then
		show_error "Epel RPM repository" "installation FAILED"
	fi

	if ( ! sed -i '/gpgcheck/s/1/0/g' /etc/yum.repos.d/epel* >> ${check_log} 2>&1 ); then
		show_error "Epel RPM repository" "Failed to disable gpgchecks in /etc/yum.repos.d/epel*"
	fi

	show_info "Epel RPM repository" "installation PASSED"

	return 1
}

function doApacheRemove () {
	show_info "Cleaning RPM httpd" "In progress"

	if [ -f "/etc/init.d/httpd" ]; then
		if ( ! cp -a /etc/init.d/httpd /etc/init.d/httpd.GEN ); then
			show_error "Cleaning RPM httpd" "cp -a /etc/init.d/httpd /etc/init.d/httpd.GEN FAILED"
		else
			show_info "Cleaning RPM httpd" "cp -a /etc/init.d/httpd /etc/init.d/httpd.GEN PASSED"
		fi
	fi

	if [ -f "$webserver_conf" ]; then
		if ( ! cp -a $webserver_conf $webserver_conf.GEN >> ${check_log} 2>&1 ); then
			show_error "Cleaning RPM httpd" "cp -a $webserver_conf $webserver_conf.GEN FAILED"
		else
			show_info "Cleaning RPM httpd" "cp -a $webserver_conf $webserver_conf.GEN PASSED"
		fi
	fi

	if ( ! rpm -e --allmatches --nodeps httpd >> ${check_log} 2>&1 ); then
		show_error "Cleaning RPM httpd" "rpm -e --allmatches --nodeps httpd FAILED"
	else
		show_info "Cleaning RPM httpd" "rpm -e --allmatches --nodeps httpd PASSED"
	fi

	if [ ! -h /etc/httpd ] && [ ! -d /etc/httpd ]; then
		ln -s /usr/local/apache /etc/httpd
	fi

	if [ -f "/etc/init.d/httpd.GEN" ]; then
		if ( ! cp -a /etc/init.d/httpd.GEN /etc/init.d/httpd >> ${check_log} 2>&1 ); then
			show_error "Cleaning RPM httpd" "cp -a /etc/init.d/httpd.GEN /etc/init.d/httpd FAILED"
		else
			show_info "Cleaning RPM httpd" "cp -a /etc/init.d/httpd.GEN /etc/init.d/httpd PASSED"
		fi
	fi

	if [ -f "$webserver_conf.GEN" ]; then
		if ( ! cp -a $webserver_conf.GEN $webserver_conf >> ${check_log} 2>&1 ); then
			show_error "Cleaning RPM httpd" "cp -a $webserver_conf.GEN $webserver_conf FAILED"
		else
			show_info "Cleaning RPM httpd" "cp -a $webserver_conf.GEN $webserver_conf PASSED"
		fi
	fi

	if ( ! /etc/init.d/httpd startssl >> ${check_log} 2>&1 ); then
		show_error "Cleaning RPM httpd" "/etc/init.d/httpd startssl FAILED"
	else
		show_info "Cleaning RPM httpd" "/etc/init.d/httpd startssl FAILED"
	fi

	show_info "Cleaning RPM httpd" "PASSED"
}

function coreLibsUpgrade () {
	if [ ! -f /usr/local/1h/bin/1h_updates.sh ]; then
		return
	fi

	show_warning "1H Libs" "Already installed ... trying to upgrade"
	show_info "1H Libs" "Updating now ..."
	if [ "${distro}" == 'debian' ]; then
		if ( ! apt-get -o Dpkg::Options::=--force-confold -y --force-yes install 1h-libs >> ${check_log} 2>&1 ); then
			show_error "apt-get -y install 1h-libs" "FAILED"
		else
			show_info "apt-get -y install 1h-libs" "PASSED"
		fi
	else
		if ( ! yum -y upgrade 1h-libs >> ${check_log} 2>&1 ); then
			show_error "yum -y upgrade 1h-libs" "FAILED"
		else
			show_info "yum -y upgrade 1h-libs" "PASSED"
		fi
	fi
}

function psqlOnBoot () {
	if [ "${distro}" == 'debian' ]; then
		if ( ! update-rc.d postgresql defaults >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL init" "update-rc.d postgresql defaults FAILED"
		fi
		if ( ! update-rc.d postgresql enable >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL init" "update-rc.d postgresql enable FAILED"
		fi
		show_info "PostgreSQL update-rc.d" "PASSED"
	else
		if ( ! chkconfig --add postgresql >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL chkconfig init" "chkconfig --add postgresql FAILED"
		fi
		if ( ! chkconfig postgresql on >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL chkconfig init" "chkconfig postgresql on FAILED"
		fi
		show_info "PostgreSQL chkconfig init" "PASSED"
	fi
}

function psqlInstall_rhel_based {
	show_info "PostgreSQL install" "in progress ..."

	for package in $(rpm -qa | grep ^postgresql | grep -v postgresql-libs-); do
		if ( ! rpm -e --allmatches --nodeps $package >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL install"  "rpm -e --allmatches --nodeps $package required for install FAILED"
		else
			show_info "PostgreSQL install"  "rpm -e --allmatches --nodeps $package required for install PASSED"
		fi
	done

	if [ "$arch" == "i686" ] && [ ! -z "$psql_pkg_suffix" ]; then
		arch="i386"
	fi

	psql_pkgs_list="postgresql${psql_pkg_suffix}.${arch} postgresql${psql_pkg_suffix}-libs.${arch} postgresql${psql_pkg_suffix}-contrib.${arch} postgresql${psql_pkg_suffix}-devel.${arch} postgresql${psql_pkg_suffix}-docs.${arch} postgresql${psql_pkg_suffix}-server.${arch} postgresql${psql_pkg_suffix}-test.${arch} postgresql-libs.${arch}"

	if ( ! yum -y install $psql_pkgs_list >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL install"  "yum -y install $psql_pkgs_list FAILED"
	else
		show_info "PostgreSQL install" "yum -y install $psql_pkgs_list PASSED"
	fi

	/etc/init.d/postgresql stop >> ${check_log} 2>&1
	sleep 5
	ps uaxwf | grep -v grep| grep postgres |  awk '{print $2}' | xargs kill -9 >> ${check_log} 2>&1

	if [ -d /var/lib/pgsql/data ] && [ ! -d /var/lib/pgsql/data.before.1h ]; then
		show_warning "PostgreSQL install" "old datadir already exists. Moving it to /var/lib/pgsql/data.before.1h"
		if ( ! mv /var/lib/pgsql/data /var/lib/pgsql/data.before.1h >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL install" "old datadir move FAILED"
		else
			show_info "PostgreSQL install" "old datadir move PASSED"
		fi
	else
		rm -rf /var/lib/pgsql/data
	fi

	if [ ! -z "$psql_pkg_suffix" ]; then
		# Temp FIX for 64 bit servers.
		if [ -f /usr/share/pgsql/conversion_create.sql ]; then
			show_warning "PostgreSQL install" "JOHAB Hack required"
			if ( ! sed -i '/JOHAB --> UTF8/,//D' /usr/share/pgsql/conversion_create.sql >> ${check_log} 2>&1 ); then
				show_error "PostgreSQL install" "JOHAB Hack FAILED"
			else
				show_info "PostgreSQL install" "JOHAB Hack PASSED"
			fi
		fi
	fi

	show_info "PostgreSQL install" "initdb now ..."
	if ( ! /etc/init.d/postgresql initdb >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL install" "initdb FAILED"
	else
		show_info "PostgreSQL install" "initdb PASSED"
	fi

	show_info "PostgreSQL install" "Starting PostgreSQL now ..."
	if ( ! /etc/init.d/postgresql start >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL install" "Starting PostgreSQL FAILED"
	else
		show_info "PostgreSQL install" "Starting PostgreSQL PASSED"
	fi

	sleep 5
}

function psqlInstall_debian {
	show_info "PostgreSQL install" "in progress ..."

	if ( ! apt-get -o Dpkg::Options::=--force-confold --force-yes -y install postgresql-8.4 >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL install"  "apt-get -y install postgresql-8.4 FAILED"
	else
		show_info "PostgreSQL install" "apt-get -y install postgresql-8.4 PASSED"
	fi
}

function psqlInstall () {
	if [ "${distro}" == 'debian' ]; then
		psqlInstall_debian
	else
		psqlInstall_rhel_based
	fi
}

function psqlUpgrade () {
	show_info "PostgreSQL upgrade" "in progress ..."

	if [ -x /etc/init.d/postgresql ]; then
		if [ ! -d /var/lib/pgsql.before.1h ]; then
			if ( ! pgrep postmaster >> ${check_log} 2>&1 ); then
				/etc/init.d/postgresql restart >> ${check_log} 2>&1
			fi
	
			sleep 5
	
			if ( ! cp -a /var/lib/pgsql /var/lib/pgsql.before.1h >> ${check_log} 2>&1 ); then
				show_error "PostgreSQL upgrade" "Backup /var/lib/pgsql FAILED"
			else
				show_info "PostgreSQL upgrade" "Backup /var/lib/pgsql PASSED"
			fi
	
			if [ -S '/tmp/.s.PGSQL.5432' ]; then
				# Make sure to allow us to connect to the DB before we try to dump its content
				psql_auth_enable
		
				if ( ! su - postgres -c "if ( ! pg_dumpall >> /var/lib/pgsql.before.1h/upgrade.dump.sql ); then exit 1; fi" >> ${check_log} 2>&1 ); then
					show_error "PostgreSQL upgrade" "pg_dumpall FAILED"
				else
					show_info "PostgreSQL upgrade" "pg_dumpall PASSED"
				fi
			fi
		fi
	
		/etc/init.d/postgresql stop >> ${check_log} 2>&1
		sleep 5
		ps uaxwf | grep -v grep| grep postgres |  awk '{print $2}' | xargs kill -9 >> ${check_log} 2>&1
	fi

	for package in $(rpm -qa | grep ^postgresql | grep -v postgresql-libs- | sort -n | uniq); do
		if ( ! rpm -e --allmatches --nodeps $package >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL upgrade" "$package removal requested by upgrade FAILED"
		else
			show_info "PostgreSQL upgrade" "$package removal requested by upgrade PASSED"
		fi
	done

	if [ "$arch" == "i686" ] && [ ! -z "$psql_pkg_suffix" ]; then
		arch="i386"
	fi

	psql_pkgs_list="postgresql${psql_pkg_suffix}.${arch} postgresql${psql_pkg_suffix}-libs.${arch} postgresql${psql_pkg_suffix}-contrib.${arch} postgresql${psql_pkg_suffix}-devel.${arch} postgresql${psql_pkg_suffix}-docs.${arch} postgresql${psql_pkg_suffix}-server.${arch} postgresql${psql_pkg_suffix}-test.${arch} postgresql-libs.${arch} apr-util.${arch}"

	if ( ! yum -y install $psql_pkgs_list >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL upgrade" "yum -y install $psql_pkgs_list FAILED"
	else
		show_info "PostgreSQL upgrade" "yum -y install $psql_pkgs_list PASSED"
	fi

	if [ -d /var/lib/pgsql/data ]; then
		rm -rf /var/lib/pgsql/data >> ${check_log} 2>&1
	fi

	# Temp FIX for 64 bit servers.
	if [ ! -z "$psql_pkg_suffix" ]; then
		if [ -f /usr/share/pgsql/conversion_create.sql ]; then
			show_warning "PostgreSQL upgrade" "JOHAB Hack required"
			if ( ! sed -i '/JOHAB --> UTF8/,//D' /usr/share/pgsql/conversion_create.sql >> ${check_log} 2>&1 ); then
				show_error "PostgreSQL upgrade" "JOHAB Hack FAILED"
			else
				show_info "PostgreSQL upgrade" "JOHAB Hack PASSED"
			fi
		fi
	fi

	show_info "PostgreSQL upgrade" "initdb now ..."
	if ( ! /etc/init.d/postgresql initdb >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL upgrade" "initdb FAILED"
	else
		show_info "PostgreSQL upgrade" "initdb PASSED"
	fi

	for pg_conf in pg_ident.conf postgresql.conf; do
		if [ ! -f /var/lib/pgsql.before.1h/data/$pg_conf ]; then
			continue
		fi
		if ( ! cp -a /var/lib/pgsql.before.1h/data/$pg_conf /var/lib/pgsql/data/ >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL upgrade" "Restoring /var/lib/pgsql.before.1h/data/$pg_conf FAILED"
		else
			show_info "PostgreSQL upgrade" "Restoring /var/lib/pgsql.before.1h/data/$pg_conf PASSED"
		fi
	done

	if ( ! sed -i '/redirect_stderr/s/\(.*\)/#\1/' /var/lib/pgsql/data/postgresql.conf >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL upgrade" "Commenting redirect_stderr in /var/lib/pgsql/data/postgresql.conf FAILED"
	else
		show_info "PostgreSQL upgrade" "Commenting redirect_stderr in /var/lib/pgsql/data/postgresql.conf PASSED"
	fi

	show_info "PostgreSQL upgrade" "Starting PostgreSQL now ..."
	if ( ! /etc/init.d/postgresql start >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL upgrade" "Starting PostgreSQL FAILED"
	else
		show_info "PostgreSQL upgrade" "Starting PostgreSQL PASSED"
	fi

	sleep 5

	# Before we try to import anything make sure to try to enable psql ident authentication
	psql_auth_enable

	# make sure to restore the dump prior copying the old pg_hba as we have a newly init db with md5 auth we do not have pass for psql user :)
	# First we have ident here, later after the restoration our client has it's own md5 probbably with a .pgpass inside the pgsql dir
	if [ -f /var/lib/pgsql.before.1h/upgrade.dump.sql ]; then
		if ( ! su - postgres -c "if ( ! psql -Upostgres template1 -f /var/lib/pgsql.before.1h/upgrade.dump.sql ); then exit 1; fi" >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL upgrade"  "Importing upgrade.dump.sql FAILED"
		else
			show_info "PostgreSQL upgrade"  "Importing upgrade.dump.sql PASSED"
		fi
	fi

    pg_hba=$(get_pghba_conf)
    psql_init=$(get_psql_init)
	if [ -f /var/lib/pgsql.before.1h/data/pg_hba.conf ]; then
		if ( ! cp -a /var/lib/pgsql.before.1h/data/pg_hba.conf $pg_hba >> ${check_log} 2>&1 ); then
			show_error "PostgreSQL upgrade"  "Restoring pg_hba.conf FAILED"
		else
			show_info "PostgreSQL upgrade"  "Restoring pg_hba.conf PASSED"
		fi
	fi

	if ( ! sed -i '/ident sameuser/s/sameuser//g' $pg_hba >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL upgrade"  "Patching pg_hba.conf FAILED"
	else
		show_info "PostgreSQL upgrade"  "Patching pg_hba.conf PASSED"
	fi

	if ( ! $psql_init reload >> ${check_log} 2>&1 ); then
		show_error "PostgreSQL upgrade"  "reload FAILED"
	else
		show_info "PostgreSQL upgrade"  "reload PASSED"
	fi

	show_info "PostgreSQL upgrade"  "COMPLETED"
}

function add_repo_excludes {
	if [ ! -f /etc/yum.repos.d/1h.repo ]; then
		show_error "1H repo" "Not found. This should not happen."
	fi

	if ( grep 'exclude.*unscd' /etc/yum.repos.d/1h.repo >> ${check_log} 2>&1 ); then
		#unscd is already excluded in the repo so we will just return
		return
	fi

	if ( ! rpm -q 1h-multistats >> ${check_log} ); then
		if ( ! echo "exclude=unscd* crond*" >> /etc/yum.repos.d/1h.repo ); then
			show_error "1H repo exclude" "Failed to add our exclude list to /etc/yum.repos.d/1h.repo"
		fi
	fi
}

function reconfigurePHPinis {
	if [ "$mod_suphp" == '1' ]; then
		# If customer was running mod_suphp prior hive install:
		# - disable cgi.fix_pathinfo 
		# - enable cgi.discard_path for php53 and php54
		baseos_phps='4 5 51 52 52s 53 54'
		basedirs='/root/baseos /var/suexec/baseos'

		# Loop on all baseos dirs
		for baseos in ${basedirs}; do
			# Loop on all php versions
			for baseos_php in ${baseos_phps}; do
				ini_file="${baseos}/usr/local/php${baseos_php}/lib/php.ini"
				ini_file_limit="${baseos}/usr/local/php${baseos_php}/etc/limits.ini"
				# If main ini file exists
				if [ -f "${ini_file}" ]; then
					# Disable cgi.fix_pathinfo
					#sed -i '/^\s*cgi.fix_pathinfo\s*=.*/D' "${ini_file}"
					#sed -i "1icgi.fix_pathinfo = 0;" "${ini_file}"
					# For php53 and php54 enable cgi.discard_path as well
					if [ "${baseos_php}" == '53' ] || [ "${baseos_php}" == '54' ]; then
						sed -i '/^\s*cgi.discard_path\s*=.*/D' "${ini_file}"
						sed -i "1icgi.discard_path = 1;" "${ini_file}"
					fi
				fi
				# If limits.ini file exists:	
				# - remove cgi.fix_pathinfo for all phs from it
				if [ -f "${ini_file_limit}" ]; then
					#sed -i '/^\s*cgi.fix_pathinfo\s*=.*/D' "${ini_file_limit}"
					# - remove cgi.discard_pat for php53 and php54 only
					if [ "${baseos_php}" == '53' ] || [ "${baseos_php}" == '54' ]; then
						sed -i '/^\s*cgi.discard_path\s*=.*/D' "${ini_file_limit}"
					fi
				fi
				# Disable cgi.fix_pathinfo by appending/creating to ini_file_limit
				# For php53 and php54 enable cgi.discard_path by appending/creating to ini_file_limit
				#echo "cgi.fix_pathinfo = 0;" >> "${ini_file_limit}"
				if [ "${baseos_php}" == '53' ] || [ "${baseos_php}" == '54' ]; then
					echo "cgi.discard_path = 1;" >> "${ini_file_limit}"
				fi
			done
		done
	fi

	ini_configurator='/usr/local/1h/sbin/setup_php.sh'
	if [ ! -x "$ini_configurator" ]; then
		return
	fi

	show_info "Replicating current php.ini core settings" "to all PHP versions part of the Hive system"
	if ( ! $ini_configurator >> ${check_log} 2>&1 ); then
		show_error "Replicating current php.ini core settings" "FAILED"
	fi

	show_info "Replicating current php.ini core settings" "PASSED"
}

function remove_repo_excludes {
	if [ ! -f /etc/yum.repos.d/1h.repo ]; then
		return
	fi
	if ( ! sed -i "/exclude/D" /etc/yum.repos.d/1h.repo  >> ${check_log} 2>&1 ); then
		show_error "1H repo excludes" "Failed to clean up our exclude list from /etc/yum.repos.d/1h.repo"
	fi
}

function enable_crond_and_nscd {
	if [ "${distro}" == 'debian' ]; then
		cron_init='/etc/init.d/cron'
		cron_name='cron'
	else
		cron_init='/etc/init.d/crond'
		cron_name='crond'
	fi

	if [ -d /usr/local/1h/lib/guardian/svcstop ]; then
		touch /usr/local/1h/lib/guardian/svcstop/crond >> ${check_log} 2>&1
		touch /usr/local/1h/lib/guardian/svcstop/nscd >> ${check_log} 2>&1
	fi

	if [ -x $cron_init ]; then
		$cron_init restart >> ${check_log} 2>&1
		chkconfig $cron_name on >> ${check_log} 2>&1
	fi
	if [ -x /etc/init.d/nscd ]; then
		if ( ! grep ^nscd /etc/passwd >> ${check_log} 2>&1 ); then
			adduser -c 'NSCD Daemon' -d / -M -r -s /sbin/nologin -u 28 nscd >> ${check_log} 2>&1
		fi	
		/etc/init.d/nscd restart >> ${check_log} 2>&1
		chkconfig nscd on >> ${check_log} 2>&1
	fi
	rm -f /usr/local/1h/lib/guardian/svcstop/crond /usr/local/1h/lib/guardian/svcstop/nscd >> ${check_log} 2>&1
}

function pluginSetup {
	plugin_conf=''
	plugin_installer='/usr/local/1h/bin/setup_cpplugin.sh'

	if [ "$1" == 'hive' ]; then
		plugin_conf='/usr/local/1h/etc/cpustats_cpanel.conf'
	elif [ "$1" == 'digits' ]; then
		plugin_conf='/usr/local/1h/etc/digits_cpanel.conf'
	else
		return
	fi

	if [ ! -f "$plugin_conf" ]; then
		return
	fi
	if [ ! -x "$plugin_installer" ]; then
		return
	fi
	if ( ! grep "^\s*dbpass.*NOPASSHERE" $plugin_conf >> ${check_log} 2>&1 ); then
		return
	fi

	show_info "Configuring cPanel plugin for" "$1"
	/usr/local/1h/bin/setup_cpplugin.sh "$1" >> ${check_log} 2>&1
}

function doChecks {
	case "$1" in
		'core')
			check_core
		;;
		'portal')
			check_portal
			getPortalState 0
		;;
		'guardian')
			check_guardian
			check_max_pids
			getPortalState 1
		;;
		'hive')
			check_hive
			check_max_pids
			getPortalState 1
		;;
		'digits')
			check_digits
			getPortalState 1
		;;
		'hawk')
			check_hawk
			getPortalState 1
		;;
		'all')
			getPortalState 1
			# Portal is not installed in all anymore so we do _not_ have to call its preinstall checks here
			#check_portal
			check_max_pids
			check_guardian
			check_hive
			check_digits
			check_hawk
		;;
		*)
			exit 1
	esac
}

function chooseCorePKGs {
	if [ "${distro}" == 'debian' ]; then
		# These are the base packages required by all other software that we will have to install
		pkgs_list='1h-libs 1h-web-libs 1h-extjs 1h-extjs-gray-theme 1h-loadgraphs'
	
		# Do not install 1h-local-interface if we are required to install portal
		# For all other installation requests we will always install 1h-local-interface as a core dependency
		if [ "$1" != 'portal' ]; then
			pkgs_list="$pkgs_list 1h-local-interface"
		fi
	else
		# These are the base packages required by all other software that we will have to install
		pkgs_list='1h-libs 1h-web-libs 1h-extjs 1h-extjs-gray-theme 1h-loadgraphs'
	
		# Do not install 1h-local-interface if we are required to install portal
		# For all other installation requests we will always install 1h-local-interface as a core dependency
		if [ "$1" != 'portal' ]; then
			pkgs_list="$pkgs_list 1h-portal-local"
		fi
	
		if [ "$control_panel" == 'cpanel' ]; then
			pkgs_list="$pkgs_list 1h-whm-plugin"
		fi
	fi

	echo "$pkgs_list"
}

function choosePortalPKGs {
	if [ "${distro}" == 'debian' ]; then
		pkgs_list='1h-portal 1h-archon'
	else
		pkgs_list='gearmand portal-web 1h-archon 1h-portal'
	fi
	echo "$pkgs_list"
}

function chooseGuardianPKGs {
	pkgs_list='guardian'
	echo "$pkgs_list"
}

function chooseHivePackageName {
	if [ "${distro}" == 'debian' ]; then
		if [ "$webserver_type" == 'apache' ]; then
			if [ "$control_panel" == 'da' ]; then
				# Change the hive package to hive-X.X-da for directadmin control panels
				hive_pkg_name="hive-$(echo $webserver_version | sed 's/\.//g')-da"
			elif [ "$control_panel" == 'plesk' ]; then
				# Change the hive package to hive-X.X-plesk for Plesk control panels
				hive_pkg_name="hive-$(echo $webserver_version | sed 's/\.//g')-plesk"
			elif [ "$control_panel" == '' ]; then
				hive_pkg_name="hive-$(echo $webserver_version | sed 's/\.//g')-plain"
			else
				show_error "This should" "Never happen. Unknown control panel while attempting to pick-up hive package name"
			fi
		else
			show_error "This should" "Never happen. Unknown webserver type while attempting to pick-up hive package name"
		fi
	else
		if [ "$webserver_type" == 'apache' ]; then
			if [ "$control_panel" == 'cpanel' ]; then
				hive_pkg_name="hive-$webserver_version"
			elif [ "$control_panel" == 'da' ]; then
				# Change the hive package to hive-X.X-da for directadmin control panels
				hive_pkg_name="hive-$webserver_version-da"
			elif [ "$control_panel" == 'plesk' ]; then
				# Change the hive package to hive-X.X-plesk for plesk control panels
				hive_pkg_name="hive-$webserver_version-plesk"
			elif [ "$control_panel" == '' ]; then
				hive_pkg_name="hive-$webserver_version-plain"
			else
				show_error "This should" "Never happen. Unknown control panel while attempting to pick-up hive package name"
			fi
		elif [ "$webserver_type" == 'litespeed' ]; then
			hive_pkg_name='hive-litespeed'
		else
			show_error "This should" "Never happen. Unknown webserver type while attempting to pick-up hive package name"
		fi
	fi

	echo "$hive_pkg_name"
}

function chooseHivePKGs {
	hive_pkg_name=$(chooseHivePackageName)

	if [ "${distro}" == 'debian' ]; then
		# These are the default packages that should be installed with all hive installations
		pkgs_list="$pkgs_list 1h-chroot 1h-baseos php4-hive php5-hive php51-hive php52-hive php52s-hive php53-hive 1h-unscd"
	
		# Pick up mod_hive
		# For litespeed pick-up new phps
		if [ "$hive_pkg_name" == 'hive-22-da' ]; then
			#hive-2.2-da
			pkgs_list="$pkgs_list modhive-22-da"
		elif [ "$hive_pkg_name" == 'hive-22-plesk' ]; then
			#hive-2.2-da
			pkgs_list="$pkgs_list modhive-22-plesk"
		elif [ "$hive_pkg_name" == 'hive-22-plain' ]; then
			#hive-2.2-plain
			pkgs_list="$pkgs_list modhive-22-plain"
		fi
		
		pkgs_list="$pkgs_list 1h-cron"
	
		# Always add 1h-multistats (daemon and web interface) to the list of pkgs_list that should be installed with hive
		pkgs_list="$pkgs_list 1h-multistats"
	
		# Decide which cpustats plugin to add depending on the control panel
		if [ "$control_panel" == 'da' ]; then
			pkgs_list="$pkgs_list 1h-cpustats-da-plugin"
		fi
	
		# Finally always add $hive_pkg_name to the list of pkgs_list that we should be installed
		# $hive_pkg_name should be installed last!
		pkgs_list="$pkgs_list"
	else
		# These are the default packages that should be installed with all hive installations
		pkgs_list="$pkgs_list 1h-chroot 1h-baseos php4 php5 php51 php52 php52s php53 php54 unscd"
	
		# Pick up mod_hive
		# For litespeed pick-up new phps
		if [ "$hive_pkg_name" == 'hive-1.3' ]; then
			#hive-1.3
			pkgs_list="$pkgs_list apache1.3 suexec-1.3 mod_cgi-1.3"
		elif [ "$hive_pkg_name" == 'hive-1.3-da' ]; then
			#hive-1.3-da
			pkgs_list="$pkgs_list apache1.3-da suexec-1.3 mod_cgi-1.3"
		elif [ "$hive_pkg_name" == 'hive-2.0' ]; then
			#hive-2.0
			pkgs_list="$pkgs_list mod_hive-2.0"
		elif [ "$hive_pkg_name" == 'hive-2.0-da' ]; then
			#hive-2.0-da
			pkgs_list="$pkgs_list mod_hive-2.0"
		elif [ "$hive_pkg_name" == 'hive-2.2' ]; then
			#hive-2.2
			pkgs_list="$pkgs_list mod_hive-2.2"
		elif [ "$hive_pkg_name" == 'hive-2.4' ]; then
			#hive-2.4
			pkgs_list="$pkgs_list mod_hive-2.4"
		elif [ "$hive_pkg_name" == 'hive-2.2-da' ]; then
			#hive-2.2-da
			pkgs_list="$pkgs_list mod_hive-2.2"
		elif [ "$hive_pkg_name" == 'hive-2.2-plesk' ]; then
			#hive-2.2-plesk
			pkgs_list="$pkgs_list mod_hive-2.2-plesk"
		elif [ "$hive_pkg_name" == 'hive-2.2-plain' ]; then
			#hive-2.2-plain
			pkgs_list="$pkgs_list mod_hive-2.2-plain"
		elif [ "$hive_pkg_name" == 'hive-litespeed' ]; then
			pkgs_list="$pkgs_list php-4.4-litespeed php-5.0-litespeed php-5.1-litespeed php-5.2-litespeed php-5.3-litespeed"
		fi
		
		# Choose the right cron package
		if [ "$hive_pkg_name" == 'hive-2.2-plesk' ]; then
			pkgs_list="$pkgs_list crond-plesk"
		else
			pkgs_list="$pkgs_list crond"
		fi
	
		# Always add 1h-multistats (daemon and web interface) to the list of pkgs_list that should be installed with hive
		pkgs_list="$pkgs_list 1h-multistats"
	
		# Decide which cpustats plugin to add depending on the control panel
		if [ "$control_panel" == 'cpanel' ]; then
			pkgs_list="$pkgs_list 1h-cPanel-plugin php-version-for-cpanel php-variables-change-for-cpanel ssh-plugin-for-cpanel"
			# If this server is with cPanel and hive is NOT for litespeed (this means it is with apache 1.3/2.0/2.2)
			# Install 1h-ssc and 1h-ssc-for-whm
			if [ "$hive_pkg_name" != 'hive-litespeed' ]; then
				pkgs_list="$pkgs_list 1h-ssc 1h-ssc-for-whm"
			fi
		elif [ "$control_panel" == 'da' ]; then
			pkgs_list="$pkgs_list 1h-cpustats-da-plugin"
		elif [ "$control_panel" == 'plesk' ]; then
			pkgs_list="$pkgs_list 1h-cpustats-plesk-plugin"
		fi
	
		# Finally always add $hive_pkg_name to the list of pkgs_list that we should be installed
		# $hive_pkg_name should be installed last!
		pkgs_list="$pkgs_list $hive_pkg_name"
	fi

	echo "$pkgs_list"
}

function chooseDigitsPKGs {
	pkgs_list="$pkgs_list digits"
	# For cPanel we always add our digits plugin
	if [ "$control_panel" == 'cpanel' ]; then
		pkgs_list="$pkgs_list 1h-cPanel-plugin"
	fi

	echo "$pkgs_list"
}

function chooseHawkPKGs {
	pkgs_list='hawk'
	echo "$pkgs_list"
}

function chooseAllPKGs {
	pkgs_list=''
	if [ "$control_panel" == 'cpanel' ]; then
		# Install Digits only if the server has cPanel installed on it
		pkgs_list="$(chooseHawkPKGs) $(chooseDigitsPKGs) $(chooseHivePKGs) $(chooseGuardianPKGs)"
	else
		# If cPanel is not available on this server in all mode install everything _but_ Digits.
		pkgs_list="$(chooseHawkPKGs) $(chooseHivePKGs) $(chooseGuardianPKGs)"
	fi
	echo "$pkgs_list"
}

function ensureCpanConfig {
	show_info "CPAN Config" "Checking CPAN configuration."

	if [ -f "/root/.cpan/CPAN/MyConfig.pm" ]; then
		cpan_var=$(perl -e 'use lib "/root/.cpan"; use CPAN::MyConfig; print keys %{$CPAN::Config};' >> ${check_log} 2>&1)
	fi
	if [ -z "$cpan_var" ]; then
		cpan_var=$(perl -e 'use CPAN::Config; print keys %{$CPAN::Config};' >> ${check_log} 2>&1)
	fi

	if [ -z "$cpan_var" ]; then
		mkdir -p /root/.cpan/CPAN >> ${check_log} 2>&1
		if ( ! wget http://sw.1h.com/install/MyConfig.pm -O /root/.cpan/CPAN/MyConfig.pm >> ${check_log} 2>&1 ); then
			echo "Unable to download MyConfig.pm from 1H repository but we will continue anyway"
		fi
	fi
}

function doInstall {
	# chooseCorePKGs return list of all pkgs_list that should be installed by default no matter which is the software we want to install
	# core pkgs_list are those on which depends all our software packages
	packages_list=$(chooseCorePKGs $1)

	# Decide which PKGs we should install based on the clients request
	# Decisions for control panel specific packages and software version specific requirements are taken inside each function
	if [ "$1" == 'all' ]; then
		packages_list="$packages_list $(chooseAllPKGs)"
	elif [ "$1" == 'portal' ]; then
		packages_list="$packages_list $(choosePortalPKGs)"
	elif [ "$1" == 'hive' ]; then
		packages_list="$packages_list $(chooseHivePKGs)"
	elif [ "$1" == 'guardian' ]; then
		packages_list="$packages_list $(chooseGuardianPKGs)"
	elif [ "$1" == 'hawk' ]; then
		packages_list="$packages_list $(chooseHawkPKGs)"
	elif [ "$1" == 'digits' ]; then
		packages_list="$packages_list $(chooseDigitsPKGs)"
	else
		show_error "Incorrect pkg name in doInstall" "This should never happen. How I ended here? Kindly send us bug report about this issue. Thanks in advance"
	fi

	# Redefine hive_pkg_name as its value gets lost in one of the subshells
	if [ "$1" == 'all' ] || [ "$1" == 'hive' ]; then
		hive_pkg_name=$(chooseHivePackageName)
	fi

	show_info "Got packages list" "$packages_list"

	# Actrual yum/rpm installation of the packages starts below
	for swPackage in $packages_list; do
		if [ "${distro}" == 'debian' ]; then
			if ( dpkg -s $swPackage 2>&1 | grep 'Status: install ok installed' >> /dev/null 2>&1 ); then
				# It is already installed so we should just continue to the next package
				# show_info "$swPackage is already installed" "Moving ahead"
				continue
			fi
		else
			if ( rpm -q $swPackage >> ${check_log} 2>&1 ); then
				# It is already installed so we should just continue to the next package
				# show_info "$swPackage is already installed" "Moving ahead"
				continue
			fi
		fi

		show_info "Installing $swPackage" "The installation of $swPackage required by $1 is now in progress. Please be patient."

		if [ "${distro}" == 'debian' ]; then
			if ( ! apt-get -o Dpkg::Options::=--force-confold --force-yes -y install $swPackage >> ${check_log} 2>&1 ); then
				show_error "$swPackage installation" "FAILED"
			else
				show_info "$swPackage installation" "PASSED"
			fi
		else
			if ( ! yum -y --disableexcludes=main --disablerepo=rpmforge* install $swPackage >> ${check_log} 2>&1 ); then
				show_error "$swPackage installation" "FAILED"
			else
				show_info "$swPackage installation" "PASSED"
			fi
		fi
		# Installation of the particular package/$swPackage should be finished if we reach this code

		# If the package we just installed was hive we should add crond and unscd to the chkconfig and we should also restart them
		if [ "$swPackage" == "$hive_pkg_name" ]; then
			enable_crond_and_nscd
		fi

		# If the package we just installed was php53 we should apply client's system wide core php.ini settings to all phps inside the baseos
		if [ "$swPackage" == 'php53-hive' ] || [ "$swPackage" == 'php54' ]; then
			reconfigurePHPinis
		fi
	done
}

function fixMailmanPerms {
	if [ -d /usr/local/cpanel/3rdparty/mailman ] && [ -d /usr/local/cpanel/3rdparty/mailman/cgi-bin ]; then
		chown 0:10 /usr/local/cpanel/3rdparty/mailman
		chown 0:10 /usr/local/cpanel/3rdparty/mailman/cgi-bin
		mkdir -p /home/nobody
	fi
}

function main {
	# Show argument
	show_info "Executed with argument"  "$1"
	
	# Perform the core checks
	doChecks "core"

	# Check the state of the postgresql now
	# psql_response 0 - psql install
	# psql_response 1 - psql upgrade
	# psql_response 2 - psql ok
	check_psql
	psql_response="$?"

	# Do the checks for the specific package here
	doChecks "$1"

	if [ "$changes_counter" -gt 0 ]; then
		echo -e "${RED}-==${WHITE} The following changes will be made on your server ${RED}==-${RESET}${BEEP}"
		for todo in "${server_changes[@]}"; do
			echo "$todo"
		done
		echo -e "${RED}-==${WHITE} The above mentioned changes will be made on your server ${RED}==-${RESET}${BEEP}"
		if [ ! -f "$auto_agreement" ]; then
			askConfirmation "Please confirm before we proceed with them"
		fi
	fi

	# It looks like Shell Fork Bomb Protection is enabled.
	# In order to save customer's server from out of memory errors thrown by mysql or postgres we will increase the limits for those users
	# cPanel guys really need to fix this issue for all system users especially for the databases ones or clients may stuck with broken databases
	# Luckily we can fix this on our own now
	if [ "$ulimit_fix" == '1' ]; then
		cpanel_ulimits_fix
	fi

	if [ "$fix_perl_perms" == '1' ]; then
		fix_file_permissions "$perl_path" "755"
	fi

	# Make sure to increase kernel.shmmax if it was previously detected as too low
	if [ "$adjust_shmmax" == "1" ]; then
		change_sysctl "kernel.shmmax" "$required_shmmax"
		change_sysctl_conf "kernel.shmmax" "$required_shmmax"
		show_info "kernel.shmmax fixed" "kernel.shmmax successfully changed to $required_shmmax"
	fi

	# Stop guardian if it is running and has to be stopped before we start taking any installation actions
	if [ "$should_stop_guardian" == "1" ]; then
		show_info "Stopping guardian" "before we begin installation"
		guardian_init stop
	fi

	# Remove RPM based httpd installations only for cPanel and DA
	#if [ "$remove_rpm_httpd" == "1" ] && [ "$control_panel" != 'plesk' ] && [ "$webserver_version" == "1.3" ]; then
	#	doApacheRemove
	#fi

	# Install MySQL-devel package if it is not already installed. It is needed for DBD::mysql
	if [ "$install_mysql_devel" == "1" ]; then
		install_mysql_devel
	fi

	if [ "$psql_response" == "0" ]; then
		# psql has to be installed
		psqlInstall
	elif [ "$psql_response" == "1" ]; then
		# psql has to be upgraded
		if [ "${distro}" == 'debian' ]; then
			show_error "Unhandled PostgreSQL upgrade" "PostgreSQL upgrade for Debian based distributions is not implemented yet. Please upgrade PostgreSQL version on your server to at least 8.4.x and start the installed again"
		fi
		psqlUpgrade
	fi

	if [ "${distro}" != 'debian' ] && [ "$remove_nss_ldap" == "1" ]; then
		# nss_ldap has to be removed
		doNssLdapErase
	fi

	if [ "$install_crond" == "1" ]; then
		# We are currently installing something different than all or hive and it looks like the machine does not have crond installed
		doCrondInstall
	fi

	if [ "$adjust_max_pid" == "1" ]; then
		change_sysctl "kernel.pid_max" "$normal_pid_limit"
		change_sysctl_conf "kernel.pid_max" "$normal_pid_limit"
		show_info "kernel.pid_max fixed" "kernel.pid_max successfully changed to $normal_pid_limit"
	fi

	# Make sure that it is up before checking the conn
	pre_psql_conn_check
	psql_auth_enable
	# Test PostgreSQL connection again
	check_psql_conn

	# Turn on PostgreSQL in the chkconfig
	psqlOnBoot

	# Unlock certain files that are known to break the installs if they are locked
	doUnlockConfigs

	# Turn off yum fastest mirror plugin as it breaks the install on machines with low RAM
	changeFastMirrorStatus 0 1

	# Install EPEL repo (1h-loadgraphs and Hive litespeed PHPs need some packages from there)
	if [ "${distro}" != 'debian' ]; then
		doEpelInstall
	fi

	# Check and install 1H repo if needed
	doRepoCheck

	# Switch the stable repo to testing please
	# Do not uncomment this line unless you are absolutely sure that you want to install 1H Software from our testing repository.
	# Bad things can happen so you have been warned :)
	# doRepoSwitch

	if [ "${distro}" == 'debian' ]; then
		doAptGetUpdate
	fi

	# If we are NOT installing hive 
	if [ "${distro}" != 'debian' ]; then
		if [ "$1" != 'hive' ]; then
			if [ -z "$control_panel" ]; then
				# We should always exclude unscd from 1h repos if we do not have control panel on this machine.
				# On such machines hive should never be installed so we do not need to be able to install unscd
				# By excluding unscd we will also prevent conflicts if gcc is not installed on this machine and we should install it later
				if [ "${distro}" != 'debian' ]; then
					add_repo_excludes
				fi
			fi
	
			if [ "$1" != 'all' ]; then
				# We should always exclude unscd from 1h repos if the particular installation request is NOT for all
				# By excluding unscd we will also prevent conflicts if gcc is not installed on this machine and we should install it later
				add_repo_excludes
			else
				remove_repo_excludes
			fi
		else
			remove_repo_excludes
		fi
	fi

	# If the 1h-libs is already installed it will be upgraded to the latest stable version first if upgrades are available
	# Else it will be automatically handled by the RPM requirements of the packages choosen for doInstall
	coreLibsUpgrade

	# Make sure that perl cpan is configured before we start to act
	ensureCpanConfig

	doInstall "$1"

	if [ "$control_panel" == 'cpanel' ]; then
		if [ "$1" == 'hive' ]; then
			fixMailmanPerms
			pluginSetup 'hive'
			if [ "$disable_statfs" == '1' ]; then
				disableStatfs
			fi
		elif [ "$1" == 'digits' ]; then
			pluginSetup 'digits'
		elif [ "$1" == 'all' ]; then
			fixMailmanPerms
			pluginSetup 'digits'
			pluginSetup 'hive'
			if [ "$disable_statfs" == '1' ]; then
				disableStatfs
			fi
		fi
	fi

	# Remove psql temp ident authentication
	psql_auth_disable

	if [ "$should_stop_guardian" == "1" ]; then
		show_info "Starting guardian" "we stopped prior this installation"
		guardian_init start
	fi

	# Enable yum fastest mirror plugin if we disabled it prior the install
	if [ "${distro}" != 'debian' ] && [ "$should_revert_fastmirror" == "1" ]; then
		changeFastMirrorStatus 1 0
	fi

	# Re-lock the confs we previously unlocked if any
	if [ "$should_relock_configs" == "1" ]; then
		doRelockConfigs
	fi

	show_info "FINISHED" "Installation successful for chosen package(s)"
}

main "$1"

exit 0
