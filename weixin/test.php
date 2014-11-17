<?php
/**
 * @title test
 * @description
 * test
 * @author zhangchunsheng423@gmail.com
 * @version V1.0
 * @date 2014-07-28
 * @copyright  Copyright (c) 2010-2014 Luomor Inc. (http://www.luomor.com)
 */
$appid = "";
$redirect_uri = urlencode("http://weixin.didiwuliu.com/weixin.php");

header("Location: https://open.weixin.qq.com/connect/oauth2/authorize?appid=$appid&redirect_uri=$redirect_uri&response_type=code&scope=snsapi_base&state=123#wechat_redirect");
exit();
