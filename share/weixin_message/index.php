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
use LaneWeChat\Core\TemplateMessage;

use LaneWeChat\Core\Media;
use LaneWeChat\Core\Menu;
use LaneWeChat\Core\AdvancedBroadcast;

include 'lanewechat/lanewechat.php';
//获取自定义菜单列表
$menuList = \LaneWeChat\Core\Menu::getMenu();

//print_r($menuList);

$access_token = AccessToken::getAccessToken();

echo $access_token;//82DeycCBfCOxDmuiVHSvVpZi_3QSM7K-UTwPiFQ0vsf_do0t4BXzh4i3urHdjpXoSdwAtJ6Kk2UXyWaOfeXgwxKDeWJs4LAm4u1_CWmMd80
// _e0f4HD4ZYGEnGOwWazXu1LI_1SXGbbYaYrwsCc6MTvP4MvZFE_QI--nM_SSxxFDFJukzKLbJorKibr10S_8pHMG-8TzBPzaEnnXRIFi-2c
// YfZzNVrZw1za9VbHzrO1qVoUjmB68br8daNQ-FrHr9tps-W_Alx3DW9Lh5sVMdJEA_JVtkAGLH0QkRhBwdO4Ly4p3U6SoM38g54QUIjnfXI
// TP8C52mT_oYtn1eCH2Nbx2VtthVm3mVRRBq5kMdzipF-Vdq0OjkLGpCNHdOg136vTUVKtX6zJgPyAwARb8l8CV-NjFpVF9PIGEbsTHsuhMc

$data = array(
    'first' => array('value' => '易到红包来啦！', 'color' => '#0A0A0A'),
    'keyword1' => array('value' => '100元', 'color' => '#CCCCCC'),
    'keyword2' => array('value' => '100元', 'color' => '#CCCCCC'),
    'remark' => array('value' => '红包用于易到用车', 'color' => '#173177'),
);

$openids = array(
    "owQ_9ZDop0U4rhAUw88AHiZzS7tI",//易到林巍
    "owQ_9ZPWV8iOEblWU6VVLQQZCEZw",//月小怡
    "owQ_9ZH0FKBpaPgXkr0EEiEfAcZA",//tangpeng
    "owQ_9ZMaVuyxxN1xU6UY_hL9VV3k",//pengyuqian
    "owQ_9ZATR1BNCOrzQD7weDixqzZc",//xianglan
    "owQ_9ZATTZFGgt_wnsf6wOJkbg1g",//mengyao
    "owQ_9ZJMdWFnvC4XKBForI7BySoQ",//huanhuan
    "owQ_9ZLnybMamb4W0jgoYvpQAaiY",//郭晓东
    "owQ_9ZA5eEtlxbtNWU8jHglOAFxk"
);

foreach($openids as $openid) {
    $touser = $openid;
    $templateId = "GBCL5EoZ4-o1eieWxLD9x6mdan-z_wKNecBrPotzFb4";
    $url = "http://www.yongche.com";

    //TemplateMessage::sendTemplateMessage($data, $touser, $templateId, $url, $topcolor = '#FF0000');
}

$filename = "./weixin.jpg";
$type = "image";

echo "<br/>";

$result = Media::upload($filename, $type);
print_r($result);
/*Array
(
    [type] => image
    [media_id] => UXFBYVOCGkZUb_UqRqIzhf00hEWcOghDgWDPg3FHb8ifpIaaXYK_d2Z4Eh5B9sqq
    [created_at] => 1417856359
)
*/

echo "<br/>";

$articles = array(
    array(
        'thumb_media_id' => 'UXFBYVOCGkZUb_UqRqIzhf00hEWcOghDgWDPg3FHb8ifpIaaXYK_d2Z4Eh5B9sqq' ,
        'author' => 'peter',//
        'title' => '易到用车',
        //'content_source_url' => 'www.yongche.com',//
        //'digest' => 'hello',//
        'show_cover_pic' => '1',//
        'content' => '<a href="http://www.yongche.com">hello</a>'
    ),
);
$mediaId = AdvancedBroadcast::uploadNews($articles);

$toUserList = array(
    "owQ_9ZATTZFGgt_wnsf6wOJkbg1g",//mengyao
    "owQ_9ZJMdWFnvC4XKBForI7BySoQ",//huanhuan
    "owQ_9ZLnybMamb4W0jgoYvpQAaiY",//郭晓东
    "owQ_9ZA5eEtlxbtNWU8jHglOAFxk"
);

$result = AdvancedBroadcast::sentNewsByOpenId($toUserList, $mediaId);
print_r($result);
/*Array
(
    [errcode] => 0
    [errmsg] => send job submission success
    [msg_id] => 2349044921
)*/