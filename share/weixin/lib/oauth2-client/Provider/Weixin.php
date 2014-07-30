<?php
/**
 * @title weixin
 * @description
 * weixin
 * @author zhangchunsheng423@gmail.org
 * @version V1.0
 * @date 2014-07-11
 * @copyright  Copyright (c) 2014-2014 Luomor Inc. (http://www.luomor.com)
 */
namespace League\OAuth2\Client\Provider;

use League\OAuth2\Client\Token\AccessToken as AccessToken;

class Weixin extends IdentityProvider {
    public $scopes = array(
        'get_user_info',
    );

    public $responseType = 'string';

    public function urlAuthorize() {
        return 'https://graph.qq.com/oauth2.0/authorize';
    }

    public function urlAccessToken() {
        return 'https://graph.qq.com/oauth2.0/token';
    }

    public function urlUserDetails(AccessToken $token) {
        return 'https://graph.qq.com/user/get_user_info?' . http_build_query([
            'access_token' => $token->accessToken,
            'oauth_consumer_key' => $this->clientId,
            'openid' => $this->getUserUid($token),
        ]);
    }

    public function userDetails($response, AccessToken $token) {
        $response = (array) $response;
        $user = new User;
        $uid = $this->getUserUid($token);
        $name = $response['nickname'];
        $imageUrl = (isset($response['figureurl_qq_2'])) ? $response['figureurl_qq_2'] : null;

        $user->exchangeArray(array(
            'uid' => $uid,
            'name' => $name,
            'imageurl' => $imageUrl,
        ));

        return $user;
    }

    public function getUserUid(AccessToken $token) {
        static $response = null;

        if ($response == null) {
            $client = $this->getHttpClient();
            $client->setBaseUrl('https://graph.qq.com/oauth2.0/me?access_token=' . $token);
            $request = $client->get()->send();
            if (preg_match('/callback\((.+?)\)/', $request->getBody(), $match)) {
                $response = json_decode($match[1]);
            }
        }

        return $this->userUid($response, $token);
    }

    public function userUid($response, AccessToken $token) {
        $token->uid = $response->openid;
        return $response->openid;
    }

    public function userEmail($response, AccessToken $token) {
        return isset($response->email) && $response->email ? $response->email : null;
    }

    public function userScreenName($response, AccessToken $token) {
        return $response->name;
    }
}