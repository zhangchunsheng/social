<?php
/**
 * @title module.config
 * @description
 * module.config
 * @author zhangchunsheng423@gmail.org
 * @version V1.0
 * @date 2014-07-31
 * @copyright  Copyright (c) 2014-2014 Luomor Inc. (http://www.luomor.com)
 */
return array(
    'controllers' => array(
        'invokables' => array(
            'Weixin\Controller\Index' => 'Weixin\Controller\IndexController',
        ),
    ),
    'router' => array(
        'routes' => array(
            'weixin' => array(
                'type'    => 'segment',
                'options' => array(
                    'route'    => '/[:action]',
                    'constraints' => array(
                        'action' => '[a-zA-Z][a-zA-Z0-9_-]*',
                    ),
                    'defaults' => array(
                        'controller' => 'Weixin\Controller\Index',
                        'action'     => 'index',
                    ),
                ),
            ),
        ),
    ),
    'translator' => array(
        'locale' => 'en_US',
        'translation_file_patterns' => array(
            array(
                'type'     => 'gettext',
                'base_dir' => __DIR__ . '/../language',
                'pattern'  => '%s.mo',
            ),
        ),
    ),
    'view_manager' => array(
        'template_path_stack' => array(
            __DIR__ . '/../view',
        ),
        'strategies' => array(
            'ViewJsonStrategy',
        ),
    ),
);