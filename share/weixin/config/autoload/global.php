<?php
/**
 * @title global
 * @description
 * global
 * @author zhangchunsheng423@gmail.org
 * @version V1.0
 * @date 2014-07-31
 * @copyright  Copyright (c) 2014-2014 Luomor Inc. (http://www.luomor.com)
 */
return array(
    'db' => array(
        'driver' => 'Pdo',
        'dsn'            => 'mysql:dbname=social;hostname=localhost',
        'username'       => 'root',
        'password'       => 'root',
        'driver_options' => array(
            PDO::MYSQL_ATTR_INIT_COMMAND => 'SET NAMES \'UTF8\''
        ),
    ),
    'service_manager' => array(
        'factories' => array(
            'Zend\Db\Adapter\Adapter' => 'Zend\Db\Adapter\AdapterServiceFactory',
        ),
    ),
);