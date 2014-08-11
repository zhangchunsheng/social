<?php
/**
 * @title index
 * @description
 * index
 * @author zhangchunsheng423@gmail.org
 * @version V1.0
 * @date 2014-07-31
 * @copyright  Copyright (c) 2014-2014 Luomor Inc. (http://www.luomor.com)
 */
namespace Weixin\Controller;

use Zend\Mvc\Controller\AbstractActionController;
use Zend\View\Model\JsonModel;
use League\OAuth2\Client\Provider\Weixin;

class IndexController extends AbstractActionController {
    /**
     * @return array|JsonModel
     */
    public function indexAction() {
        $provider = new Weixin(array(
            'clientId'  =>  'wx44d0e65f9951d33b',
            'clientSecret'  =>  '5f1c5968f3b4978932cac17492f8da71',
            'redirectUri'   =>  'http://weixin.didiwuliu.com'
        ));

        if (!isset($_GET['code'])) {
            // If we don't have an authorization code then get one
            header('Location: ' . $provider->getAuthorizationUrl(array(
                "scope" => "snsapi_base"//snsapi_userinfo
            )));
            exit;
        } else {
            // If you are using Eventbrite you will need to add the grant_type parameter (see below)
            $token = $provider->getAccessToken('authorization_code', [
                'code' => $_GET['code'],
                'grant_type' => 'authorization_code'
            ]);
            // Use this to interact with an API on the users behalf
            echo $token->accessToken;

            // Use this to get a new access token if the old one expires
            echo $token->refreshToken;

            // Number of seconds until the access token will expire, and need refreshing
            echo $token->expires;
        }
        $result = new JsonModel(array(
            'index' => 'some value',
            'success'=>true,
        ));

        return $result;
    }

    /**
     * @return JsonModel
     */
    public function snsapiUserinfoAction() {
        $result = new JsonModel(array(
            'snsapiUserinfo' => 'some value',
            'success'=>true,
        ));

        return $result;
    }

    /**
     * @return JsonModel
     */
    public function weixinAction() {
        $result = new JsonModel(array(
            'weixin' => 'some value',
            'success'=>true,
        ));

        return $result;
    }
}