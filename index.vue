<template lang="pug">
    #News
        #side
            .source(v-for='s in sources' :class='{selected: s == source}' @click='select_source(s, $event)')
                span.unread {{s.unread_size ? s.unread_size : null}}
                img.icon(:src='"icons/" + s.icon')
                span.name {{s.name}}
            
        #head
            .source(v-if='source')
                #name {{source.name}}
                a#src(:href='source.src' target='_blank') {{trim_url(source.src)}}
            #control
                button#read(@click='read_next()') 已读(Space)
                button#save(@click='save()') 保存(S)
                button#reload(@click='reload()') 刷新(R)
            .last_update(v-if='source') 最后更新: {{format_relative_date(source.last_update)}}
        
        #main
            .not_loaded(v-if='!loaded')
                p 数据较大，正在加载，大约需要 30 秒......
                
                pre.
                    <b>快捷键列表</b>
                    
                    空格    转到下一个条目
                    Tab     转到下一订阅源
                    Enter   打开原网页
                    S       保存阅读进度
                    R       重新加载
                
                p
                    b 源码
                    br
                    a(href='https://github.com/ShenHongFei/NewsHub' target='_blank') https://github.com/ShenHongFei/NewsHub
            
            .item(v-if='item')
                .head
                    a.title(:href='item.url' target='_blank')
                        .name {{space(item.title)}}
                        .href {{trim_url(item.url)}}
                    .date(v-if='item.date') {{format_relative_date(item.date)}} {{format_date(item.date)}}
                .body(v-html='item.content')
</template>


<script lang="coffee">
    window.Source = class Source
        @Item: class Item
            constructor: ({@source, @title, @url, @date, @content, @hash, @read=false, @author, @categories}={})->
                if typeof @date == 'string'
                    @date = new Date @date            
        
        
        constructor: ({
                @name
                @type
                @url
                @src
                @cookie
                @items=[]
                @last_update
                @icon
            }={})->
            def @, 'size', get: -> @items.length
            def @, 'unread_size', get: -> @items.filter((item)-> !item.read).length
            if !@src
                @src = @url
            
            if typeof @last_update == 'string'
                @last_update = new Date @last_update
            
            @items = (new Item item for item in @items)
            @
        
        
        @load_data: (datastr)->
            @sources = (new Source source for source in JSON.parse datastr)
        
        
    
    module.exports =
        data: ->
            api_root: "http://#{location.host}/News/"
            Source: Source
            sources: null
            source: null
            item: null
            readed: []
            display_all_sources: false
            loaded: false
            
        methods:
            trim_url: trim_url
            format_date: format_date
            space: (text)-> space text
            format_relative_date: (date)-> space date.relative()
            
            load: ->
                raw_text = await fetch_text @api_root + 'get' + (!location.href.match(/localhost/) && '?small' || '')
                Source.load_data raw_text
                
                @sources = Source.sources.filter (source)-> source.unread_size
                @source = @sources[0]
                @set_item()
                @loaded = true
                
            reload: ->
                @readed = []
                await @load()
                
            select_source: (source, event)->
                @source = source
                @set_item()
                @save()
                # log event
            
            read_next: -> 
                if !@item then return
                @read()
                @next_item()
            
            set_item: ->
                if !@source then return
                
                i = @source.items.indexOf @item
                
                @item = @source.items[(i+1)..]?.find (item)->
                    !item.read
            
            next_item: ->
                @set_item()
                main = document.querySelector('#main')
                main.scrollTop = 0
                main.focus()
            
            next_source: -> 
                flag = false
                for source in @sources
                    if source == @source
                        flag = true
                        continue
                    if flag && source.unread_size
                        @select_source source
                        break
            
            submit: (method, data)->
                resp = await fetch_json @api_root + method, body: data
                log resp
                resp
            
            save: (disk=false)->
                if !disk && !@readed.length then return
                
                await @submit 'read',
                    hashes: @readed.map 'hash'
                    save: disk
                
                @readed = []
            
            
            read: (item, event)->
                @readed.push @item
                @item.read = true
            
            revert: ->
                @item = @readed.pop()
                @item.read = false
            
            
            switch_sources_display: ->
                @display_all_sources = !@display_all_sources
                if @display_all_sources
                    @sources = Source?.sources
                else @sources = Source.sources.filter (source)-> source.unread_size
            
            update: ->
                await @submit 'update'
            
            
            lock:   ->
                await @submit 'lock'
            
            unlock: ->
                await @submit 'unlock'
            
        mounted: ->
            await @load()
            
            # ------------ 快捷键
            document.onkeydown = (event)=>
                key  = event.key
                ctrl  = event.getModifierState('Control')
                alt   = event.getModifierState('Alt')
                shift = event.getModifierState('Shift')
                
                if alt then return
                
                if key == 'r'
                    event.preventDefault()
                    @reload()
                    return
                    
                if key == 's'
                    event.preventDefault()
                    @save(ctrl)
                    return
                    
                if key == ' '
                    event.preventDefault()
                    if !shift
                        @read_next()
                    else
                        @revert()
                    return
                    
                if key == 'Enter'
                    event.preventDefault()
                    if window.open_in_tab
                        open_in_tab @item.url
                    else
                        window.open @item.url, '_blank'
                    return
                    
                if key == 'Tab'
                    event.preventDefault()
                    @next_source()
                    return
                    
                if key == 'q'
                    event.preventDefault()
                    @switch_sources_display()
                    return
                    
                if key == 'u'
                    event.preventDefault()
                    @update()
                    return
                    
                if ctrl && key == 'l'
                    event.preventDefault()
                    @lock()
                    return
                    
                if ctrl && key == 'L'
                    event.preventDefault()
                    @unlock()
                    return
                    
                if key == 'ArrowRight'
                    @set_item()
                    return
                    
                if key == 'ArrowLeft'
                    i = @source.items.indexOf(@item)
                    if i > 0
                        i--
                    @item = @source.items[i]
                    return
                    
</script>


<style lang="stylus">
    side_width   = 220px
    main_width   = "calc(100% - %s)" % side_width
    head_height  = 28px
    background_color  = #F3F3F3
    background_color_ = #E6E6E6
    
    body
        margin 0
        
    #News
        #side
            position absolute
            width side_width
            height 100vh
            overflow-y hidden
            background background_color
            
            
            &:hover
                overflow-y scroll
            
            .source
                padding-left 10px
                height 28px
                display flex
                align-items center
                cursor pointer
                font-size 14px
                
                span.unread
                    width 30px
                    font-weight bold
                    font-size 1.2rem
                
                img.icon
                    width 20px
                    height 20px
                    
                span.name
                    overflow-x hidden
                    margin-left 12px
                    text-overflow clip
                    white-space nowrap
                    
                
            .source.selected
                background background_color_
            
        #head
            height head_height
            position absolute
            left side_width
            width main_width
            background background_color
            
            .source
                line-height head_height
                
                #name
                    display inline-block
                    font-size 1.4rem
                    margin-left 30px
                    font-weight bold
                    
                a#src
                    display inline-block
                    text-align center
                    font-size 1.2rem
                    margin-left 40px
                    color black
                    text-decoration none
                    
            .last_update
                position absolute
                top 6px
                right 30px
                
            #control
                display inline-block
                position absolute
                right 200px
                top 4px
                
                // button#read, button#save, button#reload
                
        #main
            position absolute
            left side_width
            top head_height
            width main_width
            height "calc(100% - %s)" % head_height
            overflow-y scroll
            
            .item
                padding-top 10px
                padding-left 30px
                padding-right 20px
                // border-bottom 2px dashed #ccc
                
                .head
                    .title
                        height 60px
                        text-decoration none
                        color black
                        .name
                            font-size 2rem
                            font-weight bold
                        .href
                            margin-top 5px
                            // color #aaa
                    .date
                        margin-top 5px
                    
                .body
                    padding-top 30px
                    
                    img
                        max-width 100%
                    
                    .images
                        display inline-block
                        width 300px
                        
                        img
                            height 300px
                            width 300px
                            
                    .text
                        display inline-block
                        margin-left 20px
                        vertical-align top
                
                    #ytplayer
                        width 1280px
                        height 720px
            
            .not_loaded
                margin-top 20px
                margin-left 20px
                
                pre
                    margin-top 4px
</style>
