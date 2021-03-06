FROM ubuntu:trusty
MAINTAINER Blazej Pazera <b.pazera@oberthur.com>
# libgd2-xpm libgd2-xpm-dev mysql-server vim
RUN apt-get update && apt-get install -y \
    apt-utils \
	python2.7 \
	libperl-dev \
	mysql-client \
	apache2 \
	libapache2-mod-php5 \
	python-setuptools \
	nano \
	mc \
	php5-memcached \
	php5-geoip \
	php5-gd \
	php5-ldap \
	php5-imap \
	php5-pgsql \
	php5-mcrypt \
	sudo \
	heirloom-mailx \
	lsb-release \
	build-essential \
	apache2 \
	apache2-mpm-prefork \
	php5 \
	php5-mysql \
	php-pear \
	php5-ldap \
	php5-snmp \
	php5-gd \
	php5-sqlite \
	libmysqlclient-dev \
	rrdtool \
	librrds-perl \
	libconfig-inifiles-perl \
	libcrypt-des-perl \
	libdigest-hmac-perl \
	libdigest-sha-perl \
	libgd-gd2-perl \
	snmp \
	snmpd \
	libnet-snmp-perl \
	libsnmp-perl \
	libpng12-dev \
	postfix \
	wget \
	curl \
	iputils-ping \
	smbclient \
	libssl-dev \
	dnsutils \
	fping \
	less \
	net-tools \
	rsyslog \
	supervisor \
	aufs-tools \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*


ADD files/bashrc /.bashrc

# Install Nagios 3
# Nagios installation information from http://nagios.sourceforge.net/docs/3_0/quickstart-ubuntu.html
# NDOutils, Centreon etc. from http://en.doc.centreon.com/Docs:Centreon2

RUN useradd -m -s /bin/bash nagios
RUN bash -c "echo nagios:nagios | chpasswd"
RUN groupadd nagcmd
RUN usermod -a -G nagcmd nagios
RUN usermod -a -G nagcmd www-data
RUN mkdir -p /tmp/nagios 
WORKDIR /tmp/nagios

RUN curl -SL https://assets.nagios.com/downloads/nagioscore/releases/nagios-3.5.1.tar.gz | tar -xzv
RUN mv  /tmp/nagios/nagios /tmp/nagios/nagios-3.5.1
RUN curl -SL http://www.nagios-plugins.org/download/nagios-plugins-2.1.1.tar.gz | tar -xzv
RUN curl -SL "http://downloads.sourceforge.net/project/nagios/ndoutils-2.x/ndoutils-2.0.0/ndoutils-2.0.0.tar.gz?r=&ts=1451927776&use_mirror=kent" | tar -xzv
RUN curl -SL https://s3-eu-west-1.amazonaws.com/centreon-download/public/centreon/centreon-2.6.6.tar.gz | tar -xzv
#RUN curl -SL https://s3-eu-west-1.amazonaws.com/centreon-download/public/centreon-engine/centreon-engine-1.5.0.tar.gz
RUN chown -R root:root centreon-2.6.6

# Build Nagios
WORKDIR /tmp/nagios/nagios-3.5.1
RUN ./configure --with-command-group=nagcmd --enable-nanosleep --enable-event-broker --enable-embedded-perl --prefix=/usr/local/nagios 2>&1 | tail -n 10
RUN make all  2>&1 | tail -n 10
RUN make install
RUN make install-commandmode
RUN make install-init
VOLUME /usr/local/nagios/etc
VOLUME /usr/local/nagios/var
RUN chgrp nagios /usr/local/nagios/etc/
RUN chmod g+w /usr/local/nagios/etc/
# Initially add some configs
ADD files/nagios-init.cfg /tmp/nagios/nagios.cfg
ADD files/initialize.sh /tmp/nagios/initialize.sh
RUN chmod +x /tmp/nagios/initialize.sh
ADD files/restart-nagios.sh /restart-nagios.sh
RUN chmod +x /restart-nagios.sh
RUN cp p1.pl /usr/local/nagios/share/

RUN mkdir -p /var/log/nagios/rw
RUN chown -R nagios:nagios /var/log/nagios
RUN chmod -R 775 /var/log/nagios

# Now for the plugins
WORKDIR /tmp/nagios/nagios-plugins-2.1.1
RUN ./configure --with-nagios-user=nagios --with-nagios-group=nagios  2>&1 | tail -n 10
# The DEBUG_NDO2DB flag (only) makes ndo2db non-daemonize itself, which is necessary for supervisord.
RUN make 2>&1 | tail -n 10
RUN make install

# NDOUtils
WORKDIR /tmp/nagios/ndoutils-2.0.0
RUN bash -c "CFLAGS=-DDEBUG_NDO2DB ./configure --prefix=/usr/local/nagios/ --enable-mysql --disable-pgsql --with-ndo2db-user=nagios --with-ndo2db-group=nagios 2>&1 | tail -n 10"
RUN make 2>&1 | tail -n 10
RUN cp src/ndomod-3x.o /usr/local/nagios/bin/ndomod.o
RUN cp src/ndo2db-3x /usr/local/nagios/bin/ndo2db
RUN cp src/log2ndo /usr/local/nagios/bin/
RUN cp src/file2sock /usr/local/nagios/bin/
RUN chmod 774 /usr/local/nagios/bin/ndo*
RUN chown nagios:nagios /usr/local/nagios/bin/ndo*

# Centreon itself
WORKDIR /tmp/nagios/centreon-2.6.6/
ADD files/centreon-silent-install.txt /tmp/nagios/centreon-silent-install.txt
RUN useradd -m centreon
RUN touch /etc/init.d/nagios
RUN ./install.sh -f ../centreon-silent-install.txt
RUN sed -i '/    Allow from all/a \    Require all granted' /etc/apache2/conf-available/centreon.conf
RUN adduser centreon www-data
# move files aside so that start.sh can copy them to volume centreon-etc
RUN mv /etc/centreon /tmp/centreon-etc

#enable centron in apache2
RUN a2enconf centreon.conf

# http://museum.php.net/php5/php-5.3.1.tar.bz2
ADD files/start.sh /start.sh
ADD files/foreground.sh /etc/apache2/foreground.sh
ADD files/supervisord.conf /etc/supervisord.conf
RUN chmod 755 /start.sh
RUN chmod 755 /etc/apache2/foreground.sh
EXPOSE 80
CMD ["/bin/bash", "/start.sh"]
