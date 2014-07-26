<?php
/**
 * @title weixin
 * @description
 * weixin
 * @author zhangchunsheng423@gmail.com
 * @version V1.0
 * @date 2014-07-25
 * @copyright  Copyright (c) 2010-2014 Luomor Inc. (http://www.luomor.com)
 */
$code = $_GET["code"];
$state = $_GET["state"];

$appid = "wx44d0e65f9951d33b";
$secret = "5f1c5968f3b4978932cac17492f8da71";
$grant_type = "authorization_code";

$url = "https://api.weixin.qq.com/sns/oauth2/access_token?appid=$appid&secret=$secret&code=$code&grant_type=$grant_type";
$content = file_get_contents($url);
echo $content;