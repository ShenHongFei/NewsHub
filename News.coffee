global.Source= class Source
    ## Item
    @Item= class Item
        constructor: ({
            @source
            @title
            @url
            @date
            @content
            @hash
            @read=false
            @author
            @categories
        }={})->
            if typeof @date == 'string' then @date = new Date @date
            if !@date then @date = new Date()
    
    ## Source
    constructor: ({
        @name
        @type='rss'
        @url
        @src
        @icon='rss.ico'
        @proxy=false
        @cookie
        @items=[]
        @last_update
        @encoding
        @gzip=true
    }={})->
        if !@src then @src = @url
        
        if typeof @last_update == 'string' then @last_update = new Date @last_update
        
        @items = (new Source.Item item for item in @items)
        @
    
    def @::, 'size', get: -> @items.length
    def @::, 'unread_size', get: -> @items.filter((item)-> !item.read).length
    
    
    @RSSParser= require 'rss-parser'
    @rss_parser= new @RSSParser
    
    @logging= true
    
    ## 加载数据
    @DB= ROOT + 'News/db.json'
    
    # load data
    @load_data= (datastr)->
        @sources = (new Source source for source in JSON.parse datastr)
    
    @load_data read @DB, quiet:true
    log @DB.pad(20) + '加载完成'
    
    global.sources = @sources
    
    
    def @, 'size', get: -> @sources.length
    
    @save= -> 
        await util.promisify(fs.writeFile)(@DB, @dump_data())
        log 'DB.json 保存完成'
    
    
    @dump_data= ({small=false, unread=false}={})->
        @trim()
        JSON.stringify @sources.map (source)->
            o = {}
            assign o, source
            
            if unread
                o.items = source.items.filter(read: false)
            else
                o.items = source.items
            
            if small
                o.items = o.items[...99]
            o
        
    
    load_page: (url=@url, options)->
        await load_page assign {url, @proxy, @encoding, @gzip, retry:true}, options
    
    load_json: (url=@url, options)->
        await load_json assign {url, @proxy, @encoding, @gzip, retry:true}, options
    
    
    fix_links: ($, context=$.root(), base=@src)-> # 返回 context(cheerio element) 而非 $
        $('a', context).each -> 
            if @attribs.href then @attribs.href = new URL(@attribs.href, base).toString()
        $('img', context).each -> if @attribs.src then @attribs.src = new URL(@attribs.src, base).toString()
        context
    
    
    @compute_hash= (item, {content=false, date=false}={})->
        o = 
            title: item.title
            url: item.url
        
        if content then o.content = item.content
        if date    then o.date = item.date
        
        item.hash = hash_object o
    
    # ------------ Crawl
    crawl_rss: (processor)->
        rawfeed = await fetch
            url: @url
            proxy: @proxy
            retry: true
            headers:
                'Accept': 'application/rss+xml'
            
        result = await Source.rss_parser.parseString rawfeed
        for rss_item in result.items[...60]
            item = new Source.Item
                source    : @name
                title     : rss_item.title
                url       : rss_item.link
                date      : new Date(rss_item.isoDate) || new Date()
                content   : rss_item['content:encoded'] || rss_item.content
                author    : rss_item.creator || rss_item['dc:creator']
                categories: rss_item.categories
            await processor?.call @, item, rss_item
            item
    
    
    ## 生成 items (网页/RSS -> items)
    crawl: ->
        source = @
        
        if @type == 'html'
            $ = await @load_page()
            
            if @name.match /海贼王/
                pattern = /ONE PIECE 海贼王.*(\d{3}).*X264.*1080P.*torrent/
                return $('img[src="/view/image/filetype/torrent.gif"]')
                    .parent()
                    .filter -> $(@).text().match pattern
                    .map -> 
                        a = $(@)
                        matches = a.text().match pattern
                        new Source.Item
                            source: source.name
                            title: "ONE PIECE #{matches[1]} [1080P x264].torrent"
                            url: new URL(a.attr('href').replace(/dialog/, 'download'), source.src).toString()
                    .get()
            
            if @name.match /王垠/
                return (for a in $('li.title a').get()[...10]
                    a = $(a)
                    url = new URL(a.attr('href'), @url).toString()
                    $$ = await @load_page(url)
                    new Source.Item
                        source: @name
                        title: a.text()
                        url: url
                        content: @fix_links($$, $$('.inner')).html()
                )
            
            if @name.match /浙大计算机 硕士招生/
                return $('.news a').map ->
                        a = $(@)
                        new Source.Item
                            source: source.name
                            title: a.attr('title')
                            url: new URL(a.attr('href'), source.url).toString()
                    .get()
            
            if @name.match /浙大 研招网/
                return $('.common-news-list li').map ->
                        a = $('a', @)
                        new Source.Item
                            source: source.name
                            title: a.attr('title')
                            url: new URL(a.attr('href'), source.url).toString()
                            date: new Date($('.date', @).text())
                    .get()
            
            if @name.match /uTorrent 更新/
                return $('article').map ->
                        new Source.Item
                            source: source.name
                            title: $('h1', @).text()
                            url: $('h1 a', @).attr('href')
                            content: $('section', @).html()
                    .get()
            
            if @name.match /VCB Studio/
                return $('.article').map ->
                        a = $('h1 a', @)
                        new Source.Item
                            source: source.name
                            title: a.text().trim()
                            url: a.attr('href')
                            content: $('.content-article', @).html().replace /data-cfemail="(.*?)"/g, ''
                    .get()
            
            if @name.match /Tampermonkey 更新日志/
                return $('.social').map ->
                        new Source.Item
                            source: source.name
                            title: $('.section_head', @).text().replace(/\n/g, '').trim()
                            url: source.url
                            content: $('.section_content', @).html()
                    .get()
                
        
        if @type == 'json'
            if @name.match /PAT 新闻/
                result = await @load_json()
                return (for article in result.articles
                    await delay 1000
                    new Source.Item
                        source: @name
                        title: article.title
                        url: "https://www.patest.cn/articles/#{article.id}"
                        date: new Date article.createAt
                        content: (await @load_json "https://www.patest.cn/api/articles/#{article.id}").article.text
                )
        
        
        if @type == 'rss'
            # 不对内容进行 hash
            if @name.match /Trending|生命要浪费在美好的事/
                return await @crawl_rss (item, rss_item)->
                    Source.compute_hash item
                    
            if @name.match /My GitHub/
                return await @crawl_rss (item, rss_item)->
                    item.content = @fix_links(cheerio.load(item.content)).html()
                    Source.compute_hash item, content:false
            
            if @url.match /\/youtube/
                return await @crawl_rss (item)->
                    $ = cheerio.load item.content
                    $('iframe').after('<br>')
                    $('img').remove()
                    item.content = $.html()
            
            if @name.match /好奇心日报/
                return await @crawl_rss (item)->
                    $ = cheerio.load item.content.remove("<img src='http://img.qdaily.com/uploads/20160725026790Msgaji5TilWhj7z4.jpg-w600' alt=''>")
                    ad = $('.medium-insert-active')
                    ad.next().remove()
                    ad.remove()
                    item.content = $.html()
                    item.title = item.title.trim()
                    item.url = item.url.trim()
                    Source.compute_hash item
            
            if @name.match /TED/
                return await @crawl_rss (item, rss_item)->
                    item.content += "<img src='#{rss_item.itunes.image}'>"
            
            
            if @name.match /异次元软件世界/
                return await @crawl_rss (item)-> 
                    item.title = item.title.replace /\[来自异次元\] /, ''
                    $ = cheerio.load item.content
                    $('a[title="异次元正版数字商城"]').parent().remove()
                    $('a').filter(-> $(@).text() == '马上前往围观....').first().parent().remove()
                    item.content = $.html()
            
            if @name.match /大眼仔旭/
                return await @crawl_rss (item)-> 
                    $ = await @load_page(item.url)
                    item.content = $('.intro-box').html()
            
            
            if @name.match /大工软院 本科生通知/
                return await @crawl_rss (item)->
                    $ = await @load_page(item.url, proxy:false)
                    content = @fix_links($, $('.main_con'))
                    $('p[align="right"]')
                        .filter -> $(@).text().match /[上下]一条/
                        .remove()
                    item.content = content.html()
                
                
            if @name.match /大工软院 学院通知/
                return await @crawl_rss (item)->
                    $ = await @load_page(item.url, proxy:false)
                    content = @fix_links($, $('.c_ggfw_right'))
                    $('p[align="right"]')
                        .filter -> $(@).text().match /[上下]一条/
                        .remove()
                    item.content = content.html()
                
            if @name.match /大工本部 教务重要通告/
                return await @crawl_rss (item)->
                    $ = await @load_page(item.url, proxy:false)
                    content = @fix_links($, $('form[name="_newscontent_fromname"]'))
                    $('p[align="right"]')
                        .filter -> $(@).text().match /[上下]一条/
                        .remove()
                    item.content = content.html()
                
            if @name.match /魚·后花园/
                return await @crawl_rss (item)->
                    $ = await @load_page(item.url)
                    content = @fix_links($, $('article'))
                    item.content = content.html()
                    $('a.action', content).remove()
                    item.hash = hash_object
                        title: item.title
                        url: item.url
                        content: content.html()
                
            if @name.match /逗比根据地/
                return await @crawl_rss (item)->
                    $ = await @load_page(item.url)
                    content = @fix_links($, $('article'))
                    $('.article-social', content).remove()
                    $('a.__cf_email__').remove()
                    item.content = content.html()
                
            if @name.match /唐巧的技术博客/
                return await @crawl_rss (item)->
                    $ = cheerio.load item.content
                    item.content = @fix_links($).html()
                
            if @name.match /左岸读书/
                return await @crawl_rss (item)->
                    $ = await @load_page(item.url)
                    content = @fix_links($, $('.sectionBody'))
                    info = $('.block-meta', content).html()
                    $('.block-meta', content).html(info.replace(/阅读(.*)/, ''))
                    item.content = content.html()
                
            if @name.match /知乎每日精选/
                return await @crawl_rss (item)->
                    item.content = item.content.replace('此问题还有','').replace(/\d+ 个回答，查看全部。/, '')
            
            if @name.match /科技行者/
                return await @crawl_rss (item)->
                    item.content = item.content.remove '<p><img src="https://img.solidot.org/0/446/liiLIZF8Uh6yM.jpg" height="120" style="display:block"/></p>'
            
            if @name.match /UnionFS Commits/
                result = await @crawl_rss()
                return result.filter (item)-> !item.title.match /chore\(deps\)/
            
            if @name.match /V2EX／(杭州|分享创造)/
                return await @crawl_rss (item)->
                    item.url = item.url.replace /#.*/, ''
            
            if @name.match /小众软件/
                return await @crawl_rss (item)->
                    content = item.content
                    j = content.indexOf '<hr />'
                    if j != -1
                        item.content = content[...j]
            
            return await @crawl_rss()
    
    
    # ------------ Update
    update: ->
        try
            # if Source.logging then log "#{@name} 开始更新"
            
            items = await @crawl()
            
            ## 添加或更新 item
            
            cache = new Map
            for item in @items
                cache.set item.hash, item
            
            updated_count = 0
            for item in items
                item.hash ||= Source.compute_hash item, content:true
                
                old_item = cache.get item.hash
                if old_item
                    item.read = old_item.read
                    item.date = old_item.date
                else
                    updated_count++
                cache.set item.hash, item
                
            @items = Array.from(cache.values()).sortBy 'date'
            @last_update = new Date()
            
            if updated_count then log "#{@name} +#{updated_count}"
            else if Source.logging then log "#{@name} 0"
            
            updated_count
        catch err
            log err
            log '更新失败:', @name
            log '\n'
            global.Source.failed_sources.push @
            # debugger
    
    @update= ->
        log new Date().to_time_str(), '开始更新'
        @failed_sources = []
        @stop_flag = false
        for source in @sources
            if @stop_flag then break
            await source.update()
        if !@stop_flag then @save()
        log new Date().to_time_str(), '更新完成'
        log '更新失败的 Sources:', @failed_sources.map 'name'
        @failed_sources
    
    @update_failed= ->
        for source in @failed_sources
            await source.update()
        
    
    
    @stop= -> @stop_flag = true
    
    clear: ->
        @items = []
        @last_update = null
    
    read_all: -> for item in @items then item.read = true
    
    
    trim: -> @items = @items[-1000..]
    
    @trim: -> for source in @sources then source.trim()
    
    @read= ({hashes, source_hint, save=false}={})->
        hashes = new Set hashes
        results = for source in @sources
            if source_hint && source.name != source_hint then continue
            for item in source.items when hashes.has item.hash
                item.read = true
        if save then @save()
        results
    
    @list_size= ->
        log sources.map('size').sort (x, y)-> - (x - y)
    
    @locked= false
    @lock= -> @locked = true
    @unlock= -> @locked = false
    
    
using (global.News = {}), ->
    @FILE= ROOT + 'News/News.coffee'
    
    @reload= ->
        if @watcher then _watcher = @watcher
        clear @FILE
        require @FILE
        global.News.watcher = _watcher
    
    @hot= -> File.Watcher.run @
    @cool= -> @watcher.close()
    
    log 'News 初始化完成'


log 'News'.pad(20) + '加载完成'


repl= ->
    Source.save()
    
    News.hot()
    News.reload()
    News.init()
    
    # --- Source 更新
    Source.update()
    Source.stop()
    Source.logging = false
    
    
    Source.save()
    
    
    ## 信息查看
    debug= ->
        Source.size
        sources.map 'name'
        source = sources.find name: /考研学习/
        source = sources.find name: /前端日报/
        
        $ = cheerio.load source.items[0].content
        source.fix_links $
        
        source.crawl_rss()
        
        use source
        
        source.items[0]
        source.items[1]
        
        @url = 'https://feeds.appinn.com/appinns/'
        global.rawfeed = await fetch
            url: @url
            proxy: @proxy
            retry: true
            headers:
                'Accept': 'application/rss+xml'
        
        global.result = await Source.rss_parser.parseString rawfeed
        
                
        log $.html()
        
        source.update()
        
        source.name = '前端早报'
        
        for item in source.items
            item.content = source.fix_links(cheerio.load(item.content)).html()
        
        sources.remove source
        
        Source.save()
        
        
        items = source.items.filter title: /世界杯/
        
        
    
    ## 添加 source
    add= ->
        sources.find name: /xxx/
        
        source = new Source
            name: 'ZeroDream Blog'
            type: 'rss'
            url: 'https://lo-li.cn/feed'
            src: 'https://lo-li.cn/'
            proxy: false
            icon: 'ZeroDream.jpeg'
        
        use source
        
        # 设置图标
        icon = 'qiaker.png'
        download 'https://qiaker.cn/favicon-96x96.png', '0/News/icons/' + icon
        source.icon = icon
        
        
        # 编写 crawler
        if @name.match /小众软件/
            $('h2')
                .filter -> $(@).text().match /相关阅读/
                .map -> 
                    a = $(@)
                    new Source.Item
                        source: source.name
                        # title: a.text()[1..]
                        title: a.attr('title')
                        url: new URL(a.attr('href'), source.url).toString()
            .get()
        
        
        repl_this == global.repl_this
        # 获取 items
        result = await source.load_json()
        
        result = await source.crawl_rss()
        
        
        source.update()
        
        # 预览
        sources.push source
        
        sources.pop()
        
        Source.save()
    
    # 查重
    debug_duplicated= ->
        source = sources.find name:'小众软件'
        source.items.map 'title'
        
        items = source.items.filter title: /让 Windows 图片查看器支持 WebP 图片格式/
        
        log items[0].content
        log items[1].content
        
        copy items[0].content
        copy items[1].content
        
        items[0].content == items[1].content
        
        $ = cheerio.load items[1].content
        
        # 编写 crawler
        if @name.match /小众软件/
            content = 
            j = items[0].content.indexOf '<hr />'
            items[0].content[...j]
            items[0].content.replace /.*/m, ''
        
        
        source.clear()
        source.update()
        
        
        
    # 去重
    remove_duplicated= ->
        cache = new Map
        
        for item in source.items
            item.url = item.url.replace /#.*/, ''
            item.hash = Source.compute_hash item, content:true
            
            cache.set item.hash, item
            null
        
        for item in source.items
            content = item.content
            j = content.indexOf '<hr />'
            item.content = content[...j]
            item.hash = Source.compute_hash item, content:true
            
            cache.set item.hash, item
            null
        
        source.items.length
        cache.size
        
        source.items = Array.from(cache.values()).sortBy 'date'
        
    
    reorder_repl= ->
        source_list = Text.load('D:/0/News/sources.txt').lines.filter (line)-> line.startsWith('    ') && line.trim()
        source_list = source_list.map (name)-> name.trim()
        m = {}
        for source in @sources then m[source.name] = source
        @sources = (m[name] for name in source_list)
        log (m[name] for name in source_list).map 'name'
        
    list_diff_repl= ->
        source_list = Text.load('D:/0/News/sources.txt').lines.filter (line)-> line.startsWith('    ') && line.trim()
        source_list = source_list.map (name)-> name.trim()
        source_list_ = @sources.map 'name'
        source_list.filter((x) => !source_list_.includes(x)).concat(source_list_.filter((x) => !source_list.includes(x)))
    
    Source.lock()
    Source.unlock()
    Source.locked
    
    Source.update_failed()



