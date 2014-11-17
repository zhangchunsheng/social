<?php
/**
 * @title index
 * @description
 * index
 * @author zhangchunsheng423@gmail.com
 * @version V1.0
 * @date 2014-11-17
 * @copyright  Copyright (c) 2010-2014 Luomor Inc. (http://www.luomor.com)
 */
use LaneWeChat\Core\AccessToken;

include 'lanewechat/lanewechat.php';
//获取自定义菜单列表
$menuList = \LaneWeChat\Core\Menu::getMenu();

print_r($menuList);

$access_token = AccessToken::getAccessToken();

echo $access_token;//82DeycCBfCOxDmuiVHSvVpZi_3QSM7K-UTwPiFQ0vsf_do0t4BXzh4i3urHdjpXoSdwAtJ6Kk2UXyWaOfeXgwxKDeWJs4LAm4u1_CWmMd80