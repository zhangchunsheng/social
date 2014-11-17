<?php
/**
 * @title weixin
 * @description
 * weixin
 * @author zhangchunsheng423@gmail.com
 * @version V1.0
 * @date 2014-07-28
 * @copyright  Copyright (c) 2010-2014 Luomor Inc. (http://www.luomor.com)
 */
$code = $_GET["code"];
$state = $_GET["state"];

$appid = "";
$secret = "";
$grant_type = "authorization_code";

$url = "https://api.weixin.qq.com/sns/oauth2/access_token?appid=$appid&secret=$secret&code=$code&grant_type=$grant_type";
$content = request($url);

$info = json_decode($content);
echo "你好，" . $info->openid;

$file = fopen("weixin.txt", "a+");
fwrite($file, $content . "\n");

$url = "https://api.weixin.qq.com/cgi-bin/user/info?access_token=" . $info->access_token . "&openid=" . $info->openid . "&lang=zh_CN";
echo "<p/>";
echo $url;
echo "<p/>";
$content = request($url);
$info = json_decode($content);
print_r($info);

fwrite($file, $content . "\n");
fclose($file);

function request($url, $method = "GET", $post_fields = null, $header = array()) {
    $ch = curl_init();

    try {
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_HEADER, 0);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 5);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $header);

        if($method == "POST") {
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, $post_fields);
        }
        $result = curl_exec($ch);

        if(curl_error($ch)) {
            error_log("access $url error:" . curl_error($ch));
        }
        curl_close($ch);
    } catch(Exception $e) {
        curl_close($ch);
        throw $e;
    }

    if(empty($result)) {
        return false;
    }

    return $result;
}