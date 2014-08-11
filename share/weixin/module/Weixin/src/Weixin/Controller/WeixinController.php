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
namespace Application\Controller;

use Zend\Mvc\Controller\AbstractActionController;
use Zend\View\Model\ViewModel;

class IndexController extends AbstractActionController {
    public function indexAction() {
        return new ViewModel();
    }
}