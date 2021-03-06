#!/bin/bash

CONFIG="agent.conf.sh"
ENTERPRISE=true
PKG_MANAGERS=(apt-get zypper yum)

if [ ! -f $CONFIG ]; then
        echo "agent.conf.sh not found or not readable"
        exit 1
fi

source $CONFIG

# Which Distro are we running on...
if [ -z "$PKG_MANAGERS" ] || [ ${#PKG_MANAGERS[@]} -eq 0 ]; then
        echo "Error! No package managers specified"
        exit 1
else
        for pkg in ${PKG_MANAGERS[@]}; do
                TEST=`which $pkg`
                if [ $? -eq 0 ]; then
                	PKG_MAN=$pkg
                	break
                fi
        done
fi

if [ -z "$PKG_MAN" ]; then
	echo "No package manager found on this system!"
	exit 1
fi

if [ -z "$SYSCONTACT" ]; then
        echo "No system contact specified"
        exit 1
fi

if [ -z "$SYSLOCATION" ]; then
        echo "No system location specified"
        exit 1
fi

if [ -z "$SNMP_COMMUNITY" ]; then
        echo "No SNMP Community specified"
        exit 1
fi

if [ -z "$OBSERVIUM_HOST" ]; then
        echo "No Observium Server IP or hostname specified"
        exit 1
fi

if [ -z "$SVN_USER" ] || [ -z "$SVN_PASS" ]; then
        ENTERPRISE=false
fi


cd /opt

if [ "$ENTERPRISE" = true ]; then
        svn --username $SVN_USER --password $SVN_PASS co http://svn.observium.org/svn/observium/branches/stable observium
else
        mkdir -p /opt/observium && cd /opt

        wget http://www.observium.org/observium-community-latest.tar.gz
        tar zxvf observium-community-latest.tar.gz
fi

mv /opt/observium/scripts/distro /usr/bin/distro
chmod 755 /usr/bin/distro


if [ "$ENTERPRISE" = true ]; then
        echo "Installing Enterprise Agent..."
	echo
else
   echo "Installing Community Agent..."
   echo
   if [ "$PKG_MAN" == "apt-get" ]; then
        $PKG_MAN install snmpd xinetd
   else
        $PKG_MAN install net-snmp xinetd
   fi
fi


if [ -f "/etc/defaults/snmpd" ]; then
	sed -e "/SNMPDOPTS=/ s/^#*/SNMPDOPTS='-Lsd -Lf \/dev\/null -u snmp -p \/var\/run\/snmpd.pid'\n#/" -i /etc/default/snmpd
fi

if [ -f "/etc/sysconfig/snmpd.options" ]; then
	sed -e "/SNMPDOPTS=/ s/^#*/SNMPDOPTS='-Lsd -Lf \/dev\/null -u snmp -p \/var\/run\/snmpd.pid'\n#/" -i /etc/sysconfig/snmpd.options
fi

if [ -f "/etc/sysconfig/snmpd" ]; then
	sed -e "/SNMPDOPTS=/ s/^#*/SNMPDOPTS='-Lsd -Lf \/dev\/null -u snmp -p \/var\/run\/snmpd.pid'\n#/" -i /etc/sysconfig/snmpd
fi

mv /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.bak
cat >/etc/snmp/snmpd.conf <<EOL
com2sec readonly  default         $SNMP_COMMUNITY
group MyROGroup v1         readonly
group MyROGroup v2c        readonly
group MyROGroup usm        readonly
view all    included  .1                               80
access MyROGroup ""      any       noauth    exact  all    none   none
syslocation $SYSLOCATION
syscontact $SYSCONTACT
#This line allows Observium to detect the host OS if the distro script is installed
extend .1.3.6.1.4.1.2021.7890.1 distro /usr/bin/distro
EOL

cat >/etc/xinetd.d/observium_agent <<EOL
service observium_agent
{
        type           = UNLISTED
        port           = 36602
        socket_type    = stream
        protocol       = tcp
        wait           = no
        user           = root
        server         = /usr/bin/observium_agent
        # configure the IPv[4|6] address(es) of your Observium server here:
        only_from      = $OBSERVIUM_HOST
        # Don't be too verbose. Don't log every check. This might be
        # commented out for debugging. If this option is commented out
        # the default options will be used for this service.
        log_on_success =
        disable        = no
}
EOL

cp observium/scripts/observium_agent /usr/bin/observium_agent

mkdir -p /usr/lib/observium_agent/local

if [ -z "$MODULES" ] || [ ${#MODULES[@]} -eq 0 ]; then
        echo "No modules specified skipping..."
else
        for mod in ${MODULES[@]}; do
                cp observium/scripts/agent-local/$mod /usr/lib/observium_agent/local/
        done
fi

if [ -x /etc/init.d/xinetd ]; then 
  /etc/init.d/xinetd restart
else
  systemctl enable xinetd
  systemctl start xinetd
fi
if [ -x /etc/init.d/snmpd ]; then 
  /etc/init.d/snmpd restart
else
  systemctl disable firewalld
  systemctl stop firewalld
  systemctl enable snmpd 
  systemctl start snmpd
fi
