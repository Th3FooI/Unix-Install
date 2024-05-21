#!/bin/bash
# everything here is in functions for debugging purposes
unknown_os ()
{
    echo "unfortunately this script doesn't support this os."
    echo
    echo "Pls run this on Debian or one of it's downstream variants"
    echo
    exit 1

}

unsupported_os ()
{
    echo "wrong OS. Run this script on Debian or one of its downstream variants"
    echo
    echo "just read the README.md that came with this script"
    exit 1
}

detect_os()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    # some systems dont have lsb-release yet have the lsb_release binary and
    # vice-versa
    if [ -e /etc/lsb-release ]; then
      . /etc/lsb-release

      if [ "${ID}" = "raspbian" ]; then
        os=${ID}
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      else
        os=${DISTRIB_ID}
        dist=${DISTRIB_CODENAME}

        if [ -z "$dist" ]; then
          dist=${DISTRIB_RELEASE}
        fi
      fi

    elif [ `which lsb_release 2>/dev/null` ]; then
      dist=`lsb_release -c | cut -f2`
      os=`lsb_release -i | cut -f2 | awk '{ print tolower($1) }'`

    elif [ -e /etc/debian_version ]; then
      # some Debians have jessie/sid in their /etc/debian_version
      # while others have '6.0.7'
      os=`cat /etc/issue | head -1 | awk '{ print tolower($1) }'`
      if grep -q '/' /etc/debian_version; then
        dist=`cut --delimiter='/' -f1 /etc/debian_version`
      else
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      fi

    else
      unknown_os
    fi
  fi

  if [ -z "$dist" ]; then
    unknown_os
  fi

  # remove whitespace from OS and dist name
  os="${os// /}"
  dist="${dist// /}"

  echo "Detected operating system as $os/$dist."
}

gpg_check ()
{
  echo "Checking for gpg..."
  if command -v gpg > /dev/null; then
    echo "Detected gpg..."
  else
    echo "Installing gnupg for GPG verification..."
    apt-get install -y gnupg
    if [ "$?" -ne "0" ]; then
      echo "Unable to install GPG! Your base system has a problem; please check your default OS's package repositories because GPG should work."
      echo "Repository installation aborted."
      exit 1
    fi
  fi
}

curl_check ()
{
  echo "Checking for curl..."
  if command -v curl > /dev/null; then
    echo "Detected curl..."
  else
    echo "Installing curl..."
    apt-get install -q -y curl
    if [ "$?" -ne "0" ]; then
      echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work."
      echo "Repository installation aborted."
      exit 1
    fi
  fi
}

install_debian_keyrin ()
{
  if [ "${os,,}" = "debian" ]; then
    echo "Installing debian-archive-keyring which is needed for installing "
    echo "apt-transport-https on many Debian systems."
    apt-get install -y debian-archive-keyring &> /dev/null
  fi
}

git_check()
{
  echo "checking for git"
  if command -v git > /dev/null; then
    echo "detected git"
  else
    echo "git not detected"
    echo
    echo "attempting to install it"
    sudo apt-get update
    sudo apt-get install git
    if [ "$?" -ne "0" ]; then
      echo "Unable to install git! Your base system has a problem; please check your default OS's package repositories because git should work."
      echo 
      echo "abort"
      exit 1
    fi
  
  fi 
}

detect_apt_version ()
{
  apt_version_full=`apt-get -v | head -1 | awk '{ print $2 }'`
  apt_version_major=`echo $apt_version_full | cut -d. -f1`
  apt_version_minor=`echo $apt_version_full | cut -d. -f2`
  apt_version_modified="${apt_version_major}${apt_version_minor}0"

  echo "Detected apt version as ${apt_version_full}"
}

Kali-Repo ()
{
    cat /etc/apt/sources.list
    sudo touch /etc/apt/sources.list.d/kali.list
    sudo chmod 666 /etc/apt/sources.list.d/kali.list
    sudo echo 'deb https://http.kali.org/kali kali-rolling main non-free contrib' > /etc/apt/sources.list.d/kali.list
    sudo chmod 644 /etc/apt/sources.list.d/kali.list
    sudo apt install gnupg
    wget 'https://archive.kali.org/archive-key.asc'
    sudo apt-key add archive-key.asc
    rm archive-key.asc
}

utilities ()
{
    echo "Do you wish to install these system utilities?"
    select yn in "Yes" "No"; do
     case $yn in
        Yes ) sudo apt-get install btop mc mono-devel ; break;;
        No ) break;;
        esac
    done
}

speedtest-install ()
{
    # Need to first run apt-get update so that apt-transport-https can be
  # installed
  echo -n "Running apt-get update... "
  apt-get update &> /dev/null
  echo "done."

  # Install the debian-archive-keyring package on debian systems so that
  # apt-transport-https can be installed next
  install_debian_keyring

  echo -n "Installing apt-transport-https... "
  apt-get install -y apt-transport-https &> /dev/null
  echo "done."


  gpg_key_url="https://packagecloud.io/ookla/speedtest-cli/gpgkey"
  apt_config_url="https://packagecloud.io/install/repositories/ookla/speedtest-cli/config_file.list?os=${os}&dist=${dist}&source=script"

  apt_source_path="/etc/apt/sources.list.d/ookla_speedtest-cli.list"
  apt_keyrings_dir="/etc/apt/keyrings"
  if [ ! -d "$apt_keyrings_dir" ]; then
    install -d -m 0755 "$apt_keyrings_dir"
  fi
  gpg_keyring_path="$apt_keyrings_dir/ookla_speedtest-cli-archive-keyring.gpg"
    gpg_key_path_old="/etc/apt/trusted.gpg.d/ookla_speedtest-cli.gpg"

  echo -n "Installing $apt_source_path..."

  # create an apt config file for this repository
  curl -sSf "${apt_config_url}" > $apt_source_path
  curl_exit_code=$?

  if [ "$curl_exit_code" = "22" ]; then
    echo
    echo
    echo -n "Unable to download repo config from: "
    echo "${apt_config_url}"
    echo
    echo "This usually happens if your operating system is not supported by "
    echo "packagecloud.io, or this script's OS detection failed."
    echo
    echo "You can override the OS detection by setting os= and dist= prior to running this script."
    echo "You can find a list of supported OSes and distributions on our website: https://packagecloud.io/docs#os_distro_version"
    echo
    echo "For example, to force Ubuntu Trusty: os=ubuntu dist=trusty ./script.sh"
    echo
    echo "If you are running a supported OS, please email support@packagecloud.io and report this."
    [ -e $apt_source_path ] && rm $apt_source_path
    exit 1
  elif [ "$curl_exit_code" = "35" -o "$curl_exit_code" = "60" ]; then
    echo "curl is unable to connect to packagecloud.io over TLS when running: "
    echo "    curl ${apt_config_url}"
    echo "This is usually due to one of two things:"
    echo
    echo " 1.) Missing CA root certificates (make sure the ca-certificates package is installed)"
    echo " 2.) An old version of libssl. Try upgrading libssl on your system to a more recent version"
    echo
    echo "Contact support@packagecloud.io with information about your system for help."
    [ -e $apt_source_path ] && rm $apt_source_path
    exit 1
  elif [ "$curl_exit_code" -gt "0" ]; then
    echo
    echo "Unable to run: "
    echo "    curl ${apt_config_url}"
    echo
    echo "Double check your curl installation and try again."
    [ -e $apt_source_path ] && rm $apt_source_path
    exit 1
  else
    echo "done."
  fi

  echo -n "Importing packagecloud gpg key... "
  # import the gpg key
  curl -fsSL "${gpg_key_url}" | gpg --dearmor > ${gpg_keyring_path}
  # grant 644 permisions to gpg keyring path
  chmod 0644 "${gpg_keyring_path}"

  # move gpg key to old path if apt version is older than 1.1
  if [ "${apt_version_modified}" -lt 110 ]; then
    # move to trusted.gpg.d

    mv ${gpg_keyring_path} ${gpg_key_path_old}
    # grant 644 permisions to gpg key path
    chmod 0644 "${gpg_key_path_old}"

    # deletes the keyrings directory if it is empty
    if ! ls -1qA $apt_keyrings_dir | grep -q .;then
      rm -r $apt_keyrings_dir
    fi
    echo "Packagecloud gpg key imported to ${gpg_key_path_old}"
  else
    echo "Packagecloud gpg key imported to ${gpg_keyring_path}"
  fi
  echo "done."

  echo -n "Running apt-get update... "
  # update apt on this system
  apt-get update &> /dev/null
  echo "done."

  echo
  echo "The repository is setup! You can now install packages."
}

setup ()
{
    if [ $(id -u) -ne 0 ]; then
	    echo "This script must be run as root."
	    exit 1
    fi
  detect_os
  curl_check
  gpg_check
  git_check
  detect_apt_version

  # update apt
  sudo apt-get update
  # add kali repo
  Kali-Repo
  sudo apt-get update
  utilities
  speedtest-install
  sudo apt-get install kali-tools-hardware kali-tools-fuzzing kali-tools-802-11 kali-tools-bluetooth kali-tools-rfid kali-tools-sdr kali-tools-information-gathering kali-tools-vulnerability kali-tools-web kali-tools-database kali-tools-passwords kali-tools-wireless kali-tools-exploitation kali-tools-social-engineering kali-tools-sniffing-spoofing kali-tools-post-exploitation 
  
  if [ "$?" -ne "0" ]; then
        echo "install failed :( try checking your repositories, more likely, it's a bug in this script."
        exit 1
    fi

    echo "installation complete!"

}

setup 
exit 0 
