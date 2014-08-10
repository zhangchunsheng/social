<?php
/**
 * @title index
 * @description
 * index
 * @author zhangchunsheng423@gmail.org
 * @version V1.0
 * @date 2014-08-10
 * @copyright  Copyright (c) 2014-2014 Luomor Inc. (http://www.luomor.com)
 */
namespace Weixin\Controller;

use Zend\Mvc\Controller\AbstractActionController;
use Zend\View\Model\ViewModel;
use Zend\View\Model\JsonModel;

class WeixinController extends AbstractActionController {
    public function indexAction() {
        $result = new JsonModel(array(
            'index' => 'some value',
            'success'=>true,
        ));

        return $result;
    }
}