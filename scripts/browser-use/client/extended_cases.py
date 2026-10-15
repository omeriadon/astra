"""Expanded native APIs; successful mutations verified through separate collection reads."""
def register(cases,c,check,eventually):
    def call(name,**args):
        result=c['client'].call(name,args)
        return result['items'] if isinstance(result,dict) and 'offset' in result and 'items' in result else result
    def win(name,**args):return call(name,windowID=c['window'],**args)
    def tab(name,**args):return call(name,tabID=c['tab'],**args)
    def contains(name,key,value):return any(x.get(key)==value for x in win(name))
    cases['get_space']=lambda c:check(win('get_space',spaceID=c['space'])['spaceID']==c['space'],'space identity')
    cases['get_current_space']=lambda c:check(win('get_current_space')['spaceID']==c['space'],'selected space identity')
    cases['list_space_tabs']=lambda c:check(any(x['tabID']==c['tab'] for x in win('list_space_tabs',spaceID=c['space'])),'space tab membership')
    cases['list_space_folders']=lambda c:check(any(x['folderID']==c['folder'] for x in win('list_space_folders',spaceID=c['space'])),'space folder membership')
    def create_folder(_):
        c['extraFolder']=win('create_space_folder',spaceID=c['space'],name='Extra folder')['folderID'];check(any(x['folderID']==c['extraFolder'] for x in win('list_space_folders',spaceID=c['space'])),'space folder created')
    cases['create_space_folder']=create_folder
    def rename_folder(_):
        win('rename_space_folder',folderID=c['extraFolder'],name='Renamed extra');check(any(x['folderID']==c['extraFolder'] and x['name']=='Renamed extra' for x in win('list_space_folders',spaceID=c['space'])),'space folder renamed')
    cases['rename_space_folder']=rename_folder
    def move_folder(_):
        tab('move_tab_to_folder',spaceID=c['space'],folderID=c['extraFolder']);c['control']('grant',tabID=c['tab']);check(any(x['folderID']==c['extraFolder'] and c['tab'] in x['tabIDs'] for x in win('list_space_folders',spaceID=c['space'])),'tab folder membership')
    cases['move_tab_to_folder']=move_folder
    def move(_):
        tab('move_tab',spaceID=c['space'],area='normal');c['control']('grant',tabID=c['tab']);check(any(x['tabID']==c['tab'] for x in win('list_space_tabs',spaceID=c['space'])),'moved tab location')
    cases['move_tab']=move
    def rename(_):
        tab('rename_tab',name='Renamed fixture');check(tab('get_tab')['title']=='Renamed fixture','tab title changed')
    cases['rename_tab']=rename
    cases['unpin_tab']=lambda c:(tab('unpin_tab'),check(all(c['tab'] not in x['pinnedTabIDs'] for x in win('list_spaces')),'tab unpinned'))
    for name,value in [('favourite_tab',True),('unfavourite_tab',False)]:cases[name]=lambda c,n=name,v=value:check(tab(n)['favourite']==v,n+' membership')
    def hibernate(_):
        other=call('open_tab',url=c['page']+'&background=1',windowID=c['window'])['tabID']
        call('select_tab',tabID=other)
        result=tab('hibernate_tab');check(result['hibernated'] is True,'tab hibernated');c['control']('grant',tabID=c['tab'])
    cases['hibernate_tab']=hibernate
    def wake(_):
        tab('wake_tab');tab('wait_for_load_state',state='complete',timeout=8);check(tab('get_tab')['hibernated'] is False,'tab restored')
    cases['wake_tab']=wake
    for name,value in [('mute_tab',True),('unmute_tab',False)]:cases[name]=lambda c,n=name,v=value:(tab(n),check(tab('get_media_state')['muted']==v,n+' media state'))
    cases['get_tab_resource_usage']=lambda c:check(tab('get_tab_resource_usage')['tabID']==c['tab'],'resource tab identity')
    cases['get_tab_media_state']=lambda c:check(tab('get_tab_media_state')['tabID']==c['tab'],'media tab identity')
    def bookmark(_):
        c['extraBookmark']=win('create_bookmark',name='E2E extra bookmark',url=c['page']+'#extra')['bookmarkID'];check(contains('list_bookmarks','bookmarkID',c['extraBookmark']),'bookmark persisted')
    cases['create_bookmark']=bookmark
    cases['search_bookmarks']=lambda c:check(any(x['bookmarkID']==c['extraBookmark'] for x in win('search_bookmarks',query='E2E extra')),'bookmark search match')
    def update(_):
        win('update_bookmark',bookmarkID=c['extraBookmark'],name='E2E updated');check(any(x['bookmarkID']==c['extraBookmark'] and x['name']=='E2E updated' for x in win('list_bookmarks')),'bookmark updated')
    cases['update_bookmark']=update
    def bookmark_folder(_):
        win('create_bookmark_folder',name='E2E folder');check('E2E folder' in win('list_bookmark_folders'),'bookmark folder persisted')
    cases['create_bookmark_folder']=bookmark_folder
    cases['list_bookmark_folders']=lambda c:check('E2E folder' in win('list_bookmark_folders'),'bookmark folders read')
    def move_bookmark(_):
        win('move_bookmark',bookmarkID=c['extraBookmark'],folder='E2E folder');check(any(x['bookmarkID']==c['extraBookmark'] and x['folder']=='E2E folder' for x in win('list_bookmarks')),'bookmark folder persisted')
    cases['move_bookmark']=move_bookmark
    cases['delete_bookmark']=lambda c:(win('delete_bookmark',bookmarkID=c['extraBookmark']),check(not contains('list_bookmarks','bookmarkID',c['extraBookmark']),'bookmark deleted'))
    def search_history(_):
        result=win('search_history',query='127.0.0.1');check(bool(result),'history search fixture');c['visit']=result[0]['visitID']
    cases['search_history']=search_history
    cases['get_history_entry']=lambda c:check(win('get_history_entry',visitID=c['visit'])['visitID']==c['visit'],'history entry identity')
    def open_history(_):
        result=win('open_history_entry',visitID=c['visit']);check(any(x['tabID']==result['tabID'] for x in call('list_tabs')),'history opens shared tab')
    cases['open_history_entry']=open_history
    def open_reading(_):
        result=win('open_reading_list_item',itemID=c['itemID']);check(any(x['tabID']==result['tabID'] for x in call('list_tabs')),'reading list opens shared tab')
    cases['open_reading_list_item']=open_reading
    def remove_reading(_):
        id=tab('add_to_reading_list')['itemID'];win('remove_from_reading_list',itemID=id);check(not contains('list_reading_list','itemID',id),'reading list alias removes item')
    cases['remove_from_reading_list']=remove_reading
    cases['open_easel']=lambda c:check(win('open_easel',easelID=c['easel'])['tabID']==c['easel'],'selected easel')
    cases['get_easel_contents']=lambda c:check(win('get_easel_contents',easelID=c['easel'])['easelID']==c['easel'],'easel contents identity')
    for name in ['add_easel_text','add_easel_link','add_easel_quote']:
        def add(_,n=name):
            tab('select_tab');win('select_space',spaceID=c['space'])
            id=win(n,easelID=c['easel'],tabID=c['tab'],text='E2E content',**({'url':c['page']} if n=='add_easel_link' else {}))['itemID'];check(any(x['itemID']==id and x['text']=='E2E content' for x in win('get_easel_contents',easelID=c['easel'])['contents']['items']),'easel item persisted')
        cases[name]=add
    cases['get_boost']=lambda c:check(call('get_boost',boostID=c['boost'])['boostID']==c['boost'],'boost identity')
    def update_boost(_):
        call('update_boost',boostID=c['boost'],name='E2E Boost',css='body { border-top: 7px solid rgb(1, 2, 3); }');check(call('get_boost',boostID=c['boost'])['name']=='E2E Boost','boost update persisted')
    cases['update_boost']=update_boost
    def toggle(_):
        before=call('get_boost',boostID=c['boost'])['enabled'];call('toggle_boost',boostID=c['boost']);check(call('get_boost',boostID=c['boost'])['enabled']!=before,'boost toggled')
    cases['toggle_boost']=toggle
    cases['get_download']=lambda c:check(win('get_download',downloadID=c['download'])['downloadID']==c['download'],'download identity')
    cases['wait_for_download']=lambda c:check(win('wait_for_download',downloadID=c['download'],timeout=8)['status'] not in ['downloading','paused','finalizing'],'download terminal wait')
    # External app launches expose dispatch semantics only; no claim about Finder's UI.
    for name in ['open_download','reveal_download']:
        def external(_,n=name):
            prepare_download(c,call,win,eventually)
            result=win(n,downloadID=c['completedDownload']);check(result['requested'] is True and 'not observable' in result['postcondition'],'honest external dispatch semantics',result)
        cases[name]=external
    def delete_download(_):
        win('delete_download',downloadID=c['download']);check(not contains('list_downloads','downloadID',c['download']),'download item deleted')
    cases['delete_download']=delete_download
    cases['get_browser_status']=lambda c:check(win('get_browser_status')['windowID']==c['window'],'browser status identity')
    cases['get_download_summary']=lambda c:check(win('get_download_summary')['total']==len(win('list_downloads')),'download summary total')
    cases['get_active_media_tabs']=lambda c:check(isinstance(win('get_active_media_tabs'),list),'native active media collection')
    def search(_):
        result=win('search_web',query='astra deterministic test');check(result['tabID'] in [x['tabID'] for x in call('list_tabs')] and 'astra' in result['url'],'search tab URL constructed')
    cases['search_web']=search


def prepare_download(c,call,win,eventually):
    if 'completedDownload' in c:return
    before={x['downloadID'] for x in win('list_downloads')}
    call('navigate',tabID=c['tab'],url=c['page'].split('/?')[0]+'/download')
    eventually(lambda:any(x['downloadID'] not in before and x['status']=='completed' for x in win('list_downloads')),'known download completed')
    c['completedDownload']=next(x['downloadID'] for x in win('list_downloads') if x['downloadID'] not in before and x['status']=='completed')
