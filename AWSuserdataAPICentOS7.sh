#!/bin/bash
#Set timezone
/usr/bin/timedatectl set-timezone America/Los_Angeles
#Add auth-test.ims to hosts file
echo "164.67.134.66 iam-dc-t01.auth-test.ims iam-dc-t01" >> /etc/hosts
#Add incommon intermediate cert to CA trust
/root/.local/bin/aws s3api get-object --bucket store.logon --key incommon_interm.cer /etc/pki/ca-trust/source/anchors/incommon_interm.cer
/usr/bin/update-ca-trust
#Add package repos
yum install -y epel-release
yum-config-manager --add-repo \
http://rpms.remirepo.net/enterprise/remi.repo
yum-config-manager --disable remi-safe
yum-config-manager --enable remi-php71
cat << EOF > /etc/yum.repos.d/packages-microsoft-com-prod.repo
[packages-microsoft-com-prod]
name=packages-microsoft-com-prod
baseurl=https://packages.microsoft.com/rhel/7/prod/
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
ACCEPT_EULA='Y'
#Install packages
#yum update -y
yum install -y git gcc gcc-c++ httpd msodbcsql mssql-tools php php-devel php-intl php-ldap \
php-mbstring php-mysqlnd php-opcache php-pdo php-pecl-apcu php-process php-pecl-redis php-soap \
php-mcrypt php-xml php-pear python-pip re2c unixODBC-devel
pip install --upgrade pip
pip install --upgrade --user awscli
#Setup PHP
pecl install sqlsrv
pecl install pdo_sqlsrv
echo "extension=sqlsrv.so" > /etc/php.d/sqlsrv.ini
echo "extension=pdo_sqlsrv.so" > /etc/php.d/pdo_sqlsrv.ini
sed -i -e "s/;date.timezone =/date.timezone = 'America\/Los_Angeles'/g" /etc/php.ini
cat << EOF > /etc/profile.d/mssql-tools.sh
if ! echo $PATH | grep -q /opt/mssql-tools/bin ; then
  export PATH=$PATH:/opt/mssql-tools/bin
fi
EOF
#Install jwt keys
/root/.local/bin/aws s3api get-object --bucket encrypted.bucket --key jwt-private.pem /etc/pki/tls/private/jwt-private.pem
/root/.local/bin/aws s3api get-object --bucket encrypted.bucket --key jwt-public.pem /etc/pki/tls/certs/jwt-public.pem
chgrp apache /etc/pki/tls/private/jwt-private.pem
chmod 440 /etc/pki/tls/private/jwt-private.pem
#Configure LDAP
/root/.local/bin/aws s3api get-object --bucket store.logon --key auth-test_CA.cer /etc/openldap/certs/auth-test_CA.cer
echo "TLS_CACERT      /etc/openldap/certs/auth-test_CA.cer" > /etc/openldap/ldap.conf
echo "TLS_CACERTDIR   /etc/openldap/certs" >> /etc/openldap/ldap.conf
#Configure Apache
setsebool -P httpd_can_network_connect on
setsebool -P httpd_can_network_connect_db on
/usr/bin/mkdir /var/www/html/api
rm /etc/httpd/conf.d/welcome.conf
rm /etc/httpd/conf.d/autoindex.conf
rm /etc/httpd/conf.d/userdir.conf
sed -i -e 's/Options Indexes FollowSymLinks/Options FollowSymLinks/g' /etc/httpd/conf/httpd.conf
sed -i -e '/\<combined\>/s/%h/%{X-Forwarded-For}i %h/g' /etc/httpd/conf/httpd.conf
cat << EOF > /etc/httpd/conf.d/api.conf
<VirtualHost *:80>
  ServerName api.test.iam.ucla.edu
  DocumentRoot "/var/www/html/root"
  RewriteEngine On
  RewriteCond %{HTTP:X-Forwarded-Proto} =http
  RewriteRule . https://%{HTTP:Host}%{REQUEST_URI} [L,R=permanent]
  <Directory "/var/www/html/root">
    Options FollowSymLinks
    AllowOverride All
    Require all granted
  </Directory>
</VirtualHost>
EOF
#Deploy application code from Git
mkdir /var/www/google
/root/.local/bin/aws s3api get-object --bucket encrypted.bucket --key credentials.json /var/www/google/credentials.json
chown -R apache:apache /var/www/google
chmod 0550 /var/www/google
chmod 0440 /var/www/google/credentials.json
/root/.local/bin/aws s3api get-object --bucket encrypted.bucket --key iamucla-api-deployment.key /root/.ssh/id_rsa
chmod 400 /root/.ssh/id_rsa
ssh-keyscan github.com,192.30.255.112 >> /root/.ssh/known_hosts 2>/dev/null
ssh-keyscan 192.30.255.113 >> /root/.ssh/known_hosts 2>/dev/null
#git clone -b 'artifacts/latest' --single-branch --depth 1 git@github.com:activelamp/iamucla-api.git /var/www/html/api
git clone -b 'artifacts/qdb' --single-branch --depth 1 git@github.com:activelamp/iamucla-api.git /var/www/html/api
/root/.local/bin/aws s3api get-object --bucket encrypted.bucket --key parameters-api.yml /var/www/html/api/app/config/parameters.yml
ln -s /var/www/html/api/web /var/www/html/root
chown -R apache:apache /var/www/html/api
chmod 775 /var/www/html/api/var/cache
chmod 775 /var/www/html/api/var/logs
chmod 775 /var/www/html/api/var/sessions
restorecon -RvF /var/www/html
touch /var/log/iamucla-api-debug.log
touch /var/log/iamucla-api.log
chown apache:apache /var/log/iamucla-api*
chmod 664 /var/log/iamucla-api*
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/api/var/cache(/.*)?"
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/api/var/logs(/.*)?"
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/api/var/sessions(/.*)?"
semanage fcontext -a -t httpd_log_t /var/log/iamucla-api-debug.log
semanage fcontext -a -t httpd_log_t /var/log/iamucla-api.log
restorecon -R -v /var/www/html/api/var/cache
restorecon -R -v /var/www/html/api/var/logs
restorecon -R -v /var/www/html/api/var/sessions
restorecon -R -v /var/log/iamucla-api-debug.log
restorecon -R -v /var/log/iamucla-api.log
#Enable and start services
systemctl enable httpd
systemctl start httpd
#Create job to pull latest code
/root/.local/bin/aws s3api get-object --bucket store.logon --key api_git_pull.sh /usr/local/sbin/api_git_pull.sh
chown root:root /usr/local/sbin/api_git_pull.sh
chmod 550 /usr/local/sbin/api_git_pull.sh
echo "*/15 * * * * root /usr/local/sbin/api_git_pull.sh" > /etc/cron.d/api_git_pull
chown root:root /etc/cron.d/api_git_pull
chmod 440 /etc/crond./api_git_pull
#Install and configure CloudWatch log agent
curl https://s3.amazonaws.com//aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -O
chmod +x ./awslogs-agent-setup.py
./awslogs-agent-setup.py -n -r us-west-2 -c s3://sysadmin.logon/CWagent-api.conf
