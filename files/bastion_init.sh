#cloud-boothook
#!/usr/bin/env bash

set -e -x

KEY_UPDATER_SCRIPT=/root/update_keys.sh

# Install required packages
yum -y install telnet nc
yum -y install google-authenticator

# Configure adding google auth into pam for sshd
sed -i '1 i\# MFA auth\nauth [success=done new_authtok_reqd=done default=die] pam_google_authenticator.so' /etc/pam.d/sshd

# Updating sshd config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
cat >/etc/ssh/sshd_config <<EOF
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
SyslogFacility AUTHPRIV
PermitRootLogin forced-commands-only
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication yes
UsePAM yes
X11Forwarding yes
PrintLastLog yes
UsePrivilegeSeparation sandbox		# Default for new installations.
AuthenticationMethods publickey,keyboard-interactive
AcceptEnv LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES
AcceptEnv LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT
AcceptEnv LC_IDENTIFICATION LC_ALL LANGUAGE
AcceptEnv XMODIFIERS
Subsystem sftp	/usr/libexec/openssh/sftp-server
EOF

# Manage S3 keys
cat <<"EOF" > $${KEY_UPDATER_SCRIPT}
#!/usr/bin/env bash

set -u

BUCKET_NAME="${BUCKET}"
BUCKET_PREFIX="$$(echo ${BUCKET_PREFIX} | sed -e 's/^\///' -e 's/\/$//')"
REGION="${REGION}"
LOGFILE=/var/log/bastion/users_changelog.log
USER_LIST=/root/bastion/user.list

get_users () {
  aws s3api list-objects \
              --bucket $$BUCKET_NAME \
              --prefix $$BUCKET_PREFIX/ \
              --region $$REGION \
              --query 'CommonPrefixes[].{Prefix: Prefix}' \
              --delimiter '/' \
              --output text | awk -F'/' '{print $$(NF-1)}'
}

users_to_add () {
  USER_LIST_OLD=$$1
  USER_LIST_NEW=$$2
  diff -u $$USER_LIST_OLD $USER_LIST_NEW | tail -n +4 | egrep '^\+' | sed 's/^\+//'
}

users_to_remove () {
  USER_LIST_OLD=$$1
  USER_LIST_NEW=$$2
  diff -u $$USER_LIST_OLD $USER_LIST_NEW | tail -n +4 | egrep '^\-' | sed 's/^\-//'
}

create_user () {
  USERNAME=$$1

  if [[ "$$USERNAME" =~ ^[a-z][-a-z0-9]*$ ]]; then
    getent passwd $$USERNAME > /dev/null 2>&1
    GETENT_ECODE=$$?
    case $$GETENT_ECODE in
    2)
      /usr/sbin/useradd -m -s /bin/bash $$USERNAME &&
      mkdir -p /home/$$USERNAME/.ssh &&
      chmod 700 /home/$$USERNAME/.ssh &&
      chown $USERNAME:$$USERNAME /home/$$USERNAME/.ssh && 
      echo "`date --date="today" "+%F %H-%M-%S"`: Creating user account for $$USERNAME" >> $$LOGFILE
    ;;
    0)
      echo "`date --date="today" "+%F %H-%M-%S"`: User account for $$USERNAME already here" >> $$LOGFILE
      return 0
    ;;
    *)
      echo "`date --date="today" "+%F %H-%M-%S"`: Cannot create user $$USERNAME" >> $$LOGFILE
      return 1
    ;;
    esac

  else
    return 1
  fi
}

remove_user () {
  USERNAME=$$1

  pkill -9 -u $$USERNAME
  /usr/sbin/userdel $$USERNAME
  rm -rf /home/$$USERNAME
  echo "`date --date="today" "+%F %H-%M-%S"`: Removing user account for $$USERNAME" >> $$LOGFILE
}

update_user_key () {
  USERNAME=$$1
  aws s3api get-object --bucket $$BUCKET_NAME --key $${BUCKET_PREFIX}/$${USERNAME}/pubkey --output text /home/$$USERNAME/.ssh/authorized_keys.new
  mv /home/$$USERNAME/.ssh/authorized_keys.new /home/$$USERNAME/.ssh/authorized_keys
}

update_user_token () {
  USERNAME=$$1
  TOKEN_FILE=$$(mktemp)
  aws s3api get-object --bucket $$BUCKET_NAME --key $${BUCKET_PREFIX}/$${USERNAME}/token --output text $$TOKEN_FILE
  TOKEN=$(cat $$TOKEN_FILE)
  rm -f $$TOKEN_FILE

  cat >/home/$$USERNAME/.google_authenticator <<GAUTHENTICATOR
$$TOKEN
"RATE_LIMIT 3 30
" WINDOW_SIZE 3
" DISALLOW_REUSE
" TOTP_AUTH
GAUTHENTICATOR

  chmod 400 /home/$$USERNAME/.google_authenticator
  chown $$USERNAME.$$USERNAME /home/$$USERNAME/.google_authenticator
}

# Creating skel
mkdir -p $$(dirname $$LOGFILE)
mkdir -p $$(dirname $$USER_LIST)
touch $$USER_LIST $${USER_LIST}.prev

# Process user updates
get_users > $${USER_LIST}.new
cp -f $$USER_LIST $${USER_LIST}.prev
mv $${USER_LIST}.new $$USER_LIST

USERS_TO_ADD=$$(users_to_add $${USER_LIST}.prev $$USER_LIST)
USERS_TO_REMOVE=$$(users_to_remove $${USER_LIST}.prev $$USER_LIST)

for USER in $$USERS_TO_REMOVE; do
  remove_user $$USER
done

for USER in $$USERS_TO_ADD; do
  create_user $$USER
done

for USER in $(cat $$USER_LIST); do
  update_user_key $$USER
  update_user_token $$USER
done
EOF

# Immediate apply
chmod +x $${KEY_UPDATER_SCRIPT}
$${KEY_UPDATER_SCRIPT}

# Manage crontab
crontab -l || ERROR=$?
if [ $ERROR -ne 0 ]; then
    echo "Initializing empty crontab."
    echo '# Crontab header' | crontab -
fi

if [ -n "${UPDATE_FREQUENCY}" ]; then
  ( crontab -l | grep -v "$${KEY_UPDATER_SCRIPT}" ; echo "${UPDATE_FREQUENCY} /bin/bash -x $${KEY_UPDATER_SCRIPT} > /dev/null 2>&1" ) | crontab -
fi

# Apply security updates daily
( crontab -l | grep -v 'yum -y update' ; echo "0 5 * * * yum -y update > /dev/null 2>&1" ) | crontab -
# Restart sshd daily
( crontab -l | grep -v '/sbin/service sshd restart' ; echo "0 6 * * * /sbin/service sshd restart > /dev/null 2>&1" ) | crontab -

# Prohibit key access to root & ec2-user
rm -rf /root/.ssh /home/ec2-user/.ssh

# Apply all the changes
service sshd restart
