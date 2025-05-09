ARG BUILDER_VERSION=latest
FROM starwarsfan/edomi-baseimage:${BUILDER_VERSION}
MAINTAINER Yves Schumann <y.schumann@yetnet.ch>

# Define build arguments
ARG EDOMI_VERSION=EDOMI_203.tar
ARG ROOT_PASS=123456

# Define environment vars
ENV EDOMI_VERSION=${EDOMI_VERSION} \
    EDOMI_EXTRACT_PATH=/tmp/edomi/ \
    EDOMI_ARCHIVE=/tmp/edomi.tar \
    START_SCRIPT=/root/start.sh \
    ROOT_PASS=${ROOT_PASS} \
    EDOMI_BACKUP_DIR=/var/edomi-backups \
    EDOMI_DB_DIR=/var/lib/mysql \
    EDOMI_INSTALL_DIR=/usr/local/edomi

# Set root passwd and rename 'reboot' and 'shutdown' commands
RUN echo -e "${ROOT_PASS}\n${ROOT_PASS}" | (passwd --stdin root) \
 && mv /sbin/shutdown /sbin/shutdown_ \
 && mv /sbin/reboot /sbin/reboot_

# Replace 'reboot' and 'shutdown' with own handler scripts
COPY bin/start.sh ${START_SCRIPT}
COPY sbin/reboot sbin/shutdown sbin/service /sbin/
RUN chmod +x ${START_SCRIPT} /sbin/reboot /sbin/shutdown /sbin/service \
 && dos2unix /sbin/reboot /sbin/shutdown /sbin/service

# use a local, already extracted Edomi archive instead of downloading one
# the archive must be extracted under /tmp/edomi/
#ADD http://edomi.de/download/install/${EDOMI_VERSION} ${EDOMI_ARCHIVE}
#RUN mkdir ${EDOMI_EXTRACT_PATH} \
# && tar -xf ${EDOMI_ARCHIVE} -C ${EDOMI_EXTRACT_PATH}

# Copy modified install script into image
COPY bin/install.sh ${EDOMI_EXTRACT_PATH}

# Install Edomi
RUN cd ${EDOMI_EXTRACT_PATH} \
 && ./install.sh

# Enable ssl for edomi
# Disable chmod for not existing /dev/vcsa
# Disable removal of mysql.sock
# Replace disabled update site IP
RUN sed -i -e "\$aLoadModule log_config_module modules/mod_log_config.so" \
           -e "\$aLoadModule setenvif_module modules/mod_setenvif.so" /etc/httpd/conf.d/ssl.conf \
 && sed -i -e "s/^\(.*vcsa\)/#\1/g" \
           -e "s/\(service mysqld stop\)/#\1/g" \
           -e "s@\(rm -f \$MYSQL_PATH/mysql.sock\)@#\1@g" \
           -e "s/\(service mysqld start\)/#\1/g" /usr/local/edomi/main/start.sh \
 && sed -i -e "s/62\.75\.208\.51/edomi\.de/g" /usr/local/edomi/edomi.ini

# Nginx:
# - Backup default nginx.conf
# - Install modified nginx.conf
# - Install Edomi configuration
RUN mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.save
COPY etc/nginx/nginx.edomi.conf  /etc/nginx/nginx.conf
COPY etc/nginx/conf.d/edomi.conf /etc/nginx/conf.d/

# Enable lib_mysqludf_sys
RUN systemctl start mariadb \
 && mysql -u root mysql < /root/installdb_mysqludf_log.sql \
 && mysql -u root mysql < /root/installdb_mysqludf_sys.sql \
 && systemctl stop mariadb

# Mount points
VOLUME ${EDOMI_BACKUP_DIR} ${EDOMI_DB_DIR} ${EDOMI_INSTALL_DIR}

# Clear default root pass env var
ENV ROOT_PASS=''

CMD ["/root/start.sh"]
