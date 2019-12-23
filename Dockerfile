FROM phusion/baseimage:master
MAINTAINER Terence Kent <tkent@xetus.com>

#
# Install the baseline packages for this image. Note, these 
# packages are not version controlled and may change between
# builds.
#
RUN apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y \
    apache2\
    apache2-utils\
    libapache2-mod-fcgid\
    libfontconfig1\
    libjpeg62\
    libgd3\
    libxpm4\
    xvfb\
    ssmtp\
    ruby\
    python2.7\
    python-boto\
    perl\
    libwww-perl\
    libcrypt-ssleay-perl

#
# Instal the GPG key for the labs.consol.de repository and install 
# the repository
#
RUN curl -s "https://build.opensuse.org/projects/home:naemon/public_key" | apt-key add -
RUN echo "deb http://download.opensuse.org/repositories/home:/naemon/xUbuntu_$(lsb_release -rs)/ ./" >> /etc/apt/sources.list.d/naemon-stable.list
RUN apt-get update &&\
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nagios-nrpe-plugin\
    naemon

############################################################
# If modifying this build script, add custom packages here! #
############################################################

#
# Install jabber notification support through the sendxmpp
# project
#
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y sendxmpp
ADD notify_jabber_commands.cfg /etc/naemon/conf.d/notify_jabber_commands.cfg

#
# Install the check_http_json plugin
#
ADD https://raw.githubusercontent.com/drewkerrigan/nagios-http-json/v1.3/check_http_json.py /usr/lib/naemon/plugins/check_http_json.py
RUN sync && chmod 755 /usr/lib/naemon/plugins/check_http_json.py


#
# Enable the from line to be overridden with the ssmtp service
#
RUN  sed -i 's/^#\(FromLineOverride=.*\)/FromLineOverride=YES/' /etc/ssmtp/ssmtp.conf

ADD check_nrpe.cfg /etc/naemon/conf.d/check_nrpe.cfg
ADD thruk_root_redirect.conf /etc/apache2/conf-enabled/

#
# Perform the data directory initialization
#
ADD data_dirs.env /data_dirs.env
ADD init.bash /init.bash
# Sync calls are due to https://github.com/docker/docker/issues/9547
RUN chmod 755 /init.bash &&\
  sync && /init.bash &&\
  sync && rm /init.bash

#
# Add the bootstrap script
#
ADD run.bash /run.bash
RUN chmod 755 /run.bash

#
# All data is stored on the root data volme
#
VOLUME ["/data"]

# Expose ports for sharing
EXPOSE 80/tcp

ENTRYPOINT ["/run.bash"]
