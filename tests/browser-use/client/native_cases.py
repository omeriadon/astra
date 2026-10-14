"""Native catalog cases assert browser collection changes via independent reads."""
def register(cases,c,check,eventually):
    def call(name,**args):
        value=c['client'].call(name,args)
        return value['items'] if isinstance(value,dict) and 'items' in value and 'offset' in value else value
    def tab(name,**args):return call(name,tabID=c['tab'],**args)
    def window(name,**args):return call(name,windowID=c['window'],**args)
    def contains(name,key,value):return any(x.get(key)==value for x in window(name))
    def windows(_):check(any(x['windowID']==c['window'] for x in call('list_windows')),'isolated window listed')
    cases['list_windows']=windows
    for name in ['get_tab','get_tab_state']:
        cases[name]=lambda c,n=name: check(tab(n)['tabID']==c['tab'],n+' identity')
    def active(_):
        tab('select_tab');check(window('get_active_tab')['tabID']==c['tab'],'selected tab identity')
    cases['get_active_tab']=active;cases['select_tab']=active
    def duplicate(_):
        c['duplicate']=tab('duplicate_tab')['tabID'];check(contains_tabs(c['duplicate']),'duplicate exists')
    def contains_tabs(id):return any(x['tabID']==id for x in call('list_tabs'))
    cases['duplicate_tab']=duplicate
    def close(_):
        id=c.pop('duplicate');call('close_tab',tabID=id);check(not contains_tabs(id),'closed correct duplicate')
    cases['close_tab']=close
    def history(_):
        result=tab('get_navigation_history');check(any(c['page'].split('?')[0] in x for x in result['urls']),'visited fixture in tab history',result)
    cases['get_navigation_history']=history
    def reload(_):
        tab('reload_tab');tab('wait_for_load_state',state='complete',timeout=8);check(c['page'].split('?')[0] in tab('get_tab')['url'],'reloaded fixture URL')
    cases['reload_tab']=reload
    def back(_):
        tab('navigate',url=c['page']+'#history-a');tab('wait_for_url',url='#history-a',timeout=8)
        tab('navigate',url=c['page']+'#history-b');tab('wait_for_url',url='#history-b',timeout=8)
        tab('go_back');tab('wait_for_url',url='#history-a',timeout=8)
        check('#history-a' in tab('get_tab')['url'],'back destination')
    cases['go_back']=back
    def forward(_):
        tab('go_forward');tab('wait_for_url',url='#history-b',timeout=8)
        check('#history-b' in tab('get_tab')['url'],'forward destination')
    cases['go_forward']=forward
    def create_space(_):
        c['originalSpace']=next(x['spaceID'] for x in window('list_spaces') if c['tab'] in x['tabIDs'])
        c['space']=window('create_space')['spaceID'];check(contains('list_spaces','spaceID',c['space']),'new space listed')
    cases['create_space']=create_space
    def list_spaces(_):check(contains('list_spaces','spaceID',c['space']),'space list includes created space')
    cases['list_spaces']=list_spaces
    cases['select_space']=lambda c: check(window('select_space',spaceID=c['space'])['spaceID']==c['space'],'selected correct space')
    def rename(_):
        window('rename_space',spaceID=c['space'],name='MCP fixture space');check(any(x['spaceID']==c['space'] and x['name']=='MCP fixture space' for x in window('list_spaces')),'space rename persists')
    cases['rename_space']=rename
    def move(_):
        tab('move_tab_to_space',spaceID=c['space']);c['control']('grant',tabID=c['tab']);check(any(x['spaceID']==c['space'] and c['tab'] in x['tabIDs'] for x in window('list_spaces')),'tab moved to correct space')
    cases['move_tab_to_space']=move
    def pin(_):
        tab('pin_tab',pinned=True);check(any(c['tab'] in x['pinnedTabIDs'] for x in window('list_spaces')),'pinned tab membership')
    cases['pin_tab']=pin
    cases['set_favourite']=lambda c:check(tab('set_favourite',favourite=True)['favourite'] is True,'favourite state postcondition')
    def folder(_):
        c['folder']=window('create_pinned_folder',spaceID=c['space'],name='Fixture folder')['folderID'];check(any(x['folderID']==c['folder'] and x['name']=='Fixture folder' for x in window('list_pinned_folders',spaceID=c['space'])),'folder persists')
    cases['create_pinned_folder']=folder
    cases['list_pinned_folders']=lambda c: check(any(x['folderID']==c['folder'] for x in window('list_pinned_folders',spaceID=c['space'])),'created folder listed')
    for add,listing,key,remove in [('add_bookmark','list_bookmarks','bookmarkID','remove_bookmark'),('add_to_reading_list','list_reading_list','itemID','remove_reading_list_item')]:
        def create(_,a=add,l=listing,k=key):
            c[k]=tab(a)[k];check(contains(l,k,c[k]),a+' persisted')
        def listing_case(_,l=listing,k=key):check(contains(l,k,c[k]),l+' includes fixture')
        def remove_case(_,r=remove,l=listing,k=key):
            window(r,**{k:c[k]});check(not contains(l,k,c[k]),r+' removed correct item')
        cases[add]=create;cases[listing]=listing_case;cases[remove]=remove_case
    def easel(_):
        c['easel']=window('create_easel')['easelID'];check(contains('list_easels','easelID',c['easel']),'created easel listed')
    cases['create_easel']=easel
    cases['list_easels']=lambda c:check(contains('list_easels','easelID',c['easel']),'easel collection')
    cases['get_easel']=lambda c:check(window('get_easel',easelID=c['easel'])['easelID']==c['easel'],'easel identity')
    def boosts(_):
        c['boost']=call('create_boost',domain='127.0.0.1')['boostID'];check(any(x['boostID']==c['boost'] for x in call('list_boosts')),'boost persisted')
    cases['create_boost']=boosts
    cases['list_boosts']=lambda c:check(any(x['boostID']==c['boost'] for x in call('list_boosts')),'created boost listed')
    def enabled(_):
        call('set_boost_enabled',boostID=c['boost'],enabled=False);check(any(x['boostID']==c['boost'] and not x['enabled'] for x in call('list_boosts')),'boost disabled persists')
    cases['set_boost_enabled']=enabled
    def delete_boost(_):
        call('delete_boost',boostID=c['boost']);check(not any(x['boostID']==c['boost'] for x in call('list_boosts')),'correct boost deleted')
    cases['delete_boost']=delete_boost
    def delete_space(_):
        tab('set_favourite',favourite=False);tab('pin_tab',pinned=False);tab('move_tab_to_space',spaceID=c['originalSpace']);c['control']('grant',tabID=c['tab'])
        window('delete_space',spaceID=c['space']);check(not contains('list_spaces','spaceID',c['space']),'space removed')
    cases['delete_space']=delete_space
    cases['list_history']=lambda c:check(any(c['page'].split('?')[0] in x['url'] for x in window('list_history')),'actual visit persisted')
    def media(name):
        result=tab(name);check(result.get('tabID')==c['tab'] and ('playing' in result or 'loaded' in result),'native telemetry identity',result)
    for name in ['get_media_state','get_resource_info']:cases[name]=lambda c,n=name:media(n)
    def download(_):
        tab('navigate',url=c['page'].split('/?')[0]+'/slow-download')
        eventually(lambda:bool(window('list_downloads')),'native download creation')
        c['download']=window('list_downloads')[-1]['downloadID']
    cases['list_downloads']=download
    def cancel(_):
        window('cancel_download',downloadID=c['download']);eventually(lambda:any(x['downloadID']==c['download'] and x['status'] not in ['downloading','paused','finalizing'] for x in window('list_downloads')),'download cancelled')
    cases['cancel_download']=cancel
