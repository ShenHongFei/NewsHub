require 'lib.browser.coffee'
require 'lib/ScrollBar.styl'
require('sugar').extend()
require 'sugar/locales/zh-CN.js'
Date.setLocale('zh-CN')


using window, ->
    @Vue = require('vue').default
    
    @News = require('./index.vue').default
    
    
    @root = new Vue
        el        : '#root'
        template  : '<News ref="News"/>'
        components: {@News}
        mounted: -> log 'mounted:', window.News = @$refs.News
    
