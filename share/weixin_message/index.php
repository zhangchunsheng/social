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
include 'lanewechat/lanewechat.php';
//获取自定义菜单列表
$menuList = \LaneWeChat\Core\Menu::getMenu();

print_r($menuList);