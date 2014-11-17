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
use League\OAuth2\Client\Grant\RefreshToken;

class IndexController extends AbstractActionController {
    /**
     * @return array|JsonModel
     */
    public function indexAction() {
        $provider = new Weixin(array(
            'clientId'  =>  '',
            'clientSecret'  =>  '',
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
            header('Location: http://weixin.didiwuliu.com/snsapiUserinfo?openid=' . $token->uid);
            exit();
        }
    }

    /**
     * @return JsonModel
     */
    public function snsapiUserinfoAction() {
        $openid = $_GET["openid"];
        if(empty($openid)) {
            $result = new JsonModel(array(
                'ret_code' => 400,
                'ret_message' => "invalid param",
            ));

            return $result;
        }

        $provider = new Weixin(array(
            'clientId'  =>  '',
            'clientSecret'  =>  '',
            'redirectUri'   =>  'http://weixin.didiwuliu.com/snsapiUserinfo?openid=' . $openid
        ));

        if (!isset($_GET['code'])) {
            // If we don't have an authorization code then get one
            header('Location: ' . $provider->getAuthorizationUrl(array(
                "scope" => "snsapi_userinfo"
            )));
            exit;
        } else {
            // If you are using Eventbrite you will need to add the grant_type parameter (see below)
            $token = $provider->getAccessToken('authorization_code', [
                'code' => $_GET['code'],
                'grant_type' => 'authorization_code'
            ]);

            $grant = new RefreshToken();

            $token = $provider->getAccessToken($grant, [
                'refresh_token' => $token->refreshToken,
                'grant_type' => 'refresh_token'
            ]);

            try {
                // We got an access token, let's now get the user's details
                $userDetails = $provider->getUserDetails($token);

                // Use these details to create a new profile
                printf('<h1>Hello %s!</h1>', $userDetails->name);

                $result = new JsonModel();

                return $result;
            } catch (Exception $e) {
                // Failed to get user details
                exit('Oh dear...');
            }
        }
    }
}