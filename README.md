social
======

social app like weixin

<VirtualHost *:80>
    ServerName social.luomor.org

    DocumentRoot /home/zhang/dev/github/social/share/weixin/public
    <Directory /home/zhang/dev/github/social/share/weixin/public>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    SetEnv APPLICATION_ENV "development"

    DirectoryIndex index.php

    ErrorLog /var/log/apache2/social-weixin_error_log
    CustomLog /var/log/apache2/social-weixin_access_log combined
</VirtualHost>

<VirtualHost *:80>
    ServerName weixin.didiwuliu.com

    DocumentRoot /var/www/html/social/share/weixin/public
    <Directory /var/www/html/social/share/weixin/public>
        Options Indexes FollowSymLinks
        AllowOverride None
        Order allow,deny
        Allow from all
    </Directory>

    SetEnv APPLICATION_ENV "development"

    DirectoryIndex index.php

    ErrorLog /var/log/http/social-weixin_error_log
    CustomLog /var/log/http/social-weixin_access_log combined
</VirtualHost>
