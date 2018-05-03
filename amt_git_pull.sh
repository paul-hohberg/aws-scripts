#!/bin/bash
/bin/rm -rf /var/www/html/thor
/bin/rm -rf /var/www/html/root
/bin/git clone -b 'artifacts/latest' --single-branch --depth 1 git@github.com:activelamp/iamucla-logon.git /var/www/html/thor
/root/.local/bin/aws s3api get-object --bucket encrypted.bucket --key parameters-amt.yml /var/www/html/thor/app/config/parameters.yml
/bin/ln -s /var/www/html/thor/web /var/www/html/root
/bin/chown -R apache:apache /var/www/html/thor
/bin/chmod 775 /var/www/html/thor/var/cache
/bin/chmod 775 /var/www/html/thor/var/logs
/bin/chmod 775 /var/www/html/thor/var/sessions
/sbin/restorecon -RvF /var/www/html
/sbin/semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/thor/var/cache(/.*)?"
/sbin/semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/thor/var/logs(/.*)?"
/sbin/semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/thor/var/sessions(/.*)?"
/sbin/restorecon -R -v /var/www/html/thor/var/cache
/sbin/restorecon -R -v /var/www/html/thor/var/logs
/sbin/restorecon -R -v /var/www/html/thor/var/sessions
#sudo -u apache /usr/bin/php /var/www/html/thor/bin/console cache:clear -e=prod
#sudo -u apache /usr/bin/php /var/www/html/thor/bin/console cache:warmup -e=prod
