#!/bin/bash
#Set timezone
/usr/bin/timedatectl set-timezone America/Los_Angeles
#Add incommon intermediate cert to CA trust
/root/.local/bin/aws s3api get-object --bucket store.logon --key incommon_interm.cer /etc/pki/ca-trust/source/anchors/incommon_interm.cer
/usr/bin/update-ca-trust
#Add package repos
yum install -y epel-release
yum-config-manager --add-repo \
http://rpms.remirepo.net/enterprise/remi.repo
yum-config-manager --disable remi-safe
yum-config-manager --enable remi-php71
cat << EOF > /etc/yum.repos.d/security_shibboleth.repo
[security_shibboleth]
name=Shibboleth (CentOS_7)
type=rpm-md
baseurl=http://downloadcontent.opensuse.org/repositories/security:/shibboleth/CentOS_7/
gpgcheck=1
gpgkey=http://downloadcontent.opensuse.org/repositories/security:/shibboleth/CentOS_7/repodata/repomd.xml.key
enabled=1
EOF
#yum-config-manager --add-repo \
#http://download.opensuse.org/repositories/security:/shibboleth/CentOS_7/security:shibboleth.repo
#Install packages
#yum update -y
yum install -y git httpd php php-intl php-ldap php-mbstring php-mcrypt php-mysqlnd \
php-opcache php-pdo php-pdo-dblib php-pecl-apcu php-process php-pecl-redis \
php-soap php-xml  python-pip shibboleth
pip install --upgrade pip
pip install --upgrade --user awscli
#Set PHP timezone
sed -i -e "s/;date.timezone =/date.timezone = 'America\/Los_Angeles'/g" /etc/php.ini
#Create Shibboleth selinux module
cat << EOF > /tmp/mod_shib-to-shibd.te
module mod_shib-to-shibd 1.0;

require {
        type var_run_t;
        type httpd_t;
        type initrc_t;
        class sock_file write;
        class unix_stream_socket connectto;
}

#============= httpd_t ==============
allow httpd_t initrc_t:unix_stream_socket connectto;
allow httpd_t var_run_t:sock_file write;
EOF
checkmodule -m -M -o mod_shib-to-shibd.mod /tmp/mod_shib-to-shibd.te 
semodule_package -o mod_shib-to-shibd.pp -m mod_shib-to-shibd.mod
semodule -i mod_shib-to-shibd.pp
#Configure Shibboleth
sed -i -e 's/sp.example.org\/shibboleth/accounts-test.iam.ucla.edu\/shibboleth-sp/g' /etc/shibboleth/shibboleth2.xml
sed -i -e 's/eppn persistent-id targeted-id/SHIBEDUPERSONPRINCIPALNAME/g' /etc/shibboleth/shibboleth2.xml
sed -i -e 's/handlerSSL="false" cookieProps="http"/handlerSSL="true" cookieProps="https"/g' /etc/shibboleth/shibboleth2.xml
sed -i -e 's/idp.example.org/shbqa.ais.ucla.edu/g' /etc/shibboleth/shibboleth2.xml
sed -i -e 's/<!-- Example of locally maintained metadata. -->/\<MetadataProvider type="XML" file="testshib-two-metadata.shbqa.xml"\/\>/g' /etc/shibboleth/shibboleth2.xml
/root/.local/bin/aws s3api get-object --bucket secure.store.logon --key sp-key.pem /etc/shibboleth/sp-key.pem
/root/.local/bin/aws s3api get-object --bucket store.logon --key sp-cert.pem /etc/shibboleth/sp-cert.pem
/root/.local/bin/aws s3api get-object --bucket store.logon --key inc-md-cert.pem /etc/shibboleth/inc-md-cert.pem
/root/.local/bin/aws s3api get-object --bucket store.logon --key testshib-two-metadata.shbqa.xml /etc/shibboleth/testshib-two-metadata.shbqa.xml
#sed -i '/Shibboleth.sso/a \
#RewriteCond %{REQUEST_URI}/Shibboleth.sso/?(.*) -U \
#RewriteRule .? - [L]' /etc/httpd/conf.d/shib.conf
#Configure Apache
setsebool -P httpd_can_network_connect on
setsebool -P httpd_can_network_connect_db on
/usr/bin/mkdir /var/www/html/thor
rm /etc/httpd/conf.d/welcome.conf
rm /etc/httpd/conf.d/autoindex.conf
rm /etc/httpd/conf.d/userdir.conf
sed -i -e 's/Options Indexes FollowSymLinks/Options FollowSymLinks/g' /etc/httpd/conf/httpd.conf
sed -i -e '/\<combined\>/s/%h/%{X-Forwarded-For}i %h/g' /etc/httpd/conf/httpd.conf
cat << EOF > /etc/httpd/conf.d/accounts-test.conf
<VirtualHost *:80>
  ServerName https://accounts-test.iam.ucla.edu
  ServerAlias accounts-test.iam.ucla.edu
  DocumentRoot "/var/www/html/root"
  RewriteEngine On
  RewriteCond %{HTTP:X-Forwarded-Proto} =http
  RewriteRule . https://%{HTTP:Host}%{REQUEST_URI} [L,R=permanent]
  <Directory "/var/www/html/root">
    Options FollowSymLinks Includes
    AllowOverride All
    AuthType None
    Require all granted
  </Directory>
  <Location />
    AuthType Shibboleth
    ShibRequestSetting requireSession false
    ShibUseHeaders On
    Require shibboleth
  </Location>
  <Location /bol/verify>
    AuthType Shibboleth
    ShibRequestSetting requireSession 1
    ShibUseHeaders On
    Require valid-user
  </Location>
  <Location /logout>
    AuthType Shibboleth
    ShibRequestSetting requireSession 1
    ShibUseHeaders On
    Require valid-user
  </Location>
  <Location /mfa>
    AuthType Shibboleth
    ShibRequestSetting requireSession 1
    ShibUseHeaders On
    Require valid-user
  </Location>
  <Location /#>
    RewriteEngine On
    RewriteRule .? %{ENV:BASE}/app.php [L]
  </Location>
</VirtualHost>
EOF
#Deploy application code from Git
/root/.local/bin/aws s3api get-object --bucket secure.store.logon --key ALgitDplyKey /root/.ssh/id_rsa
chmod 400 /root/.ssh/id_rsa
ssh-keyscan github.com,192.30.255.112,192.30.255.113 >> /root/.ssh/known_hosts 2>/dev/null
#ssh-keyscan 192.30.255.113 >> /root/.ssh/known_hosts 2>/dev/null
git clone -b 'artifacts/latest' --single-branch --depth 1 git@github.com:activelamp/iamucla-logon.git /var/www/html/thor
/root/.local/bin/aws s3api get-object --bucket encrypted.bucket --key parameters-amt.yml /var/www/html/thor/app/config/parameters.yml
ln -s /var/www/html/thor/web /var/www/html/root
chown -R apache:apache /var/www/html/thor
chmod 775 /var/www/html/thor/var/cache
chmod 775 /var/www/html/thor/var/logs
chmod 775 /var/www/html/thor/var/sessions
restorecon -RvF /var/www/html
touch /var/log/thor-mfa-debug.log
touch /var/log/thor-mfa.log
chown apache:apache /var/log/thor-mfa*
chmod 664 /var/log/thor-mfa*
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/thor/var/cache(/.*)?"
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/thor/var/logs(/.*)?"
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/thor/var/sessions(/.*)?"
semanage fcontext -a -t httpd_log_t /var/log/thor-mfa-debug.log
semanage fcontext -a -t httpd_log_t /var/log/thor-mfa.log
restorecon -R -v /var/www/html/thor/var/cache
restorecon -R -v /var/www/html/thor/var/logs
restorecon -R -v /var/www/html/thor/var/sessions
restorecon -R -v /var/log/thor-mfa-debug.log
restorecon -R -v /var/log/thor-mfa.log
#Enable and start services
systemctl enable shibd
systemctl enable httpd
systemctl start shibd
systemctl start httpd
#Create job to pull latest code
/root/.local/bin/aws s3api get-object --bucket store.logon --key amt_git_pull.sh /usr/local/sbin/amt_git_pull.sh
chown root:root /usr/local/sbin/amt_git_pull.sh
chmod 550 /usr/local/sbin/amt_git_pull.sh
echo "*/15 * * * * root /usr/local/sbin/amt_git_pull.sh" > /etc/cron.d/amt_git_pull
chown root:root /etc/cron.d/amt_git_pull
chmod 440 /etc/crond./amt_git_pull
#Install and configure CloudWatch log agent
curl https://s3.amazonaws.com//aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -O
chmod +x ./awslogs-agent-setup.py
./awslogs-agent-setup.py -n -r us-west-2 -c s3://sysadmin.logon/CWagent-thor.conf
