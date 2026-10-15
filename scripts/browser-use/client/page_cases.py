"""Executable real-page postconditions; never substitutes a browser mock."""
import base64
import struct


def register(cases, c, check, eventually):
    def call(name, **args):
        return c['client'].call(name, {'tabID': c['tab'], **args})
    def js(expression):
        result = call('evaluate_javascript', expression=expression, contentWorld='page')
        return result.get('result', result) if isinstance(result, dict) else result
    def assert_js(expression, label):
        result = js(expression)
        check(result is True, label, result)
    def action(name, args, key, expected):
        call(name, **args)
        eventually(lambda: c['state']().get(key) == expected, f'{name}: {key}={expected!r}')
    for name, selector, key in [('double_click','#fixture-double','doubles'), ('right_click','#fixture-right','contexts'), ('hover','#fixture-hover','hovers')]:
        cases[name] = lambda c, n=name,s=selector,k=key: action(n, {'selector':s}, k, c['state']().get(k,0)+1)
    cases['move_pointer'] = lambda c: action('move_pointer', {'selector':'#fixture-hover'}, 'pointerTarget', 'fixture-hover')
    cases['type_text'] = lambda c: action('type_text', {'selector':'#fixture-text','value':' appended'}, 'text', 'Astra filled appended')
    cases['clear_field'] = lambda c: action('clear_field', {'selector':'#fixture-text'}, 'text', '')
    cases['set_checked'] = lambda c: action('set_checked', {'selector':'#fixture-checkbox','checked':True}, 'checkbox', True)
    cases['select_radio'] = lambda c: action('select_radio', {'selector':'#fixture-radio'}, 'radio', True)
    def submit(_):
        call('fill', selector='#fixture-required', value='valid')
        action('submit_form', {'selector':'#fixture-form'}, 'formSubmits', 1)
    cases['submit_form'] = submit
    for name, key in [('press_key','lastKey'), ('key_down','lastKey'), ('key_up','lastKeyUp')]:
        cases[name] = lambda c,n=name,k=key: action(n, {'selector':'#fixture-text','key':'F8'}, k, 'F8')
    cases['focus_element'] = lambda c: action('focus_element', {'selector':'#fixture-textarea'}, 'focused', 'fixture-textarea')
    cases['blur_element'] = lambda c: action('blur_element', {'selector':'#fixture-textarea'}, 'blurred', 'fixture-textarea')
    def drag(name):
        refs = call('find_elements', selector='#fixture-drop')['elements']
        check(len(refs)==1, 'drop target reference', refs)
        action(name, {'selector':'#fixture-drag','targetRef':refs[0]['ref']}, 'dragDrops', c['state']().get('dragDrops',0)+1)
    for name in ['drag','drag_and_drop']:
        cases[name] = lambda c,n=name: drag(n)
    def scroll(name):
        args = {'dy':73} if name=='scroll' else {'selector':'#fixture-scroll','dy':73}
        call(name, **args)
        assert_js('scrollY>0' if name=='scroll' else "document.querySelector('#fixture-scroll').scrollTop>0", name+' actual offset')
    for name in ['scroll','scroll_element']:
        cases[name]=lambda c,n=name: scroll(n)
    def scroll_view(_):
        call('scroll_into_view', selector='#fixture-offscreen')
        assert_js("(()=>{const r=document.querySelector('#fixture-offscreen').getBoundingClientRect();return r.top>=0&&r.bottom<=innerHeight})()", 'offscreen target now visible')
    cases['scroll_into_view']=scroll_view
    def read(name):
        selector='#fixture-click'
        result=call(name, selector=selector)
        if name=='find_elements': check(any(x['name']=='Increment counter' for x in result['elements']),name,result)
        elif name in ['inspect_element','get_element_state']: check(result['role']=='button' and result['name']=='Increment counter',name,result)
        elif name=='get_element_attributes': check(result['attributes']['id']=='fixture-click',name,result)
        elif name=='get_element_geometry': check(result['width']>0 and result['height']>0,name,result)
        elif name=='get_element_text': check(result['text']=='Increment counter',name,result)
        elif name=='get_dom_fragment': check('fixture-click' in result['html'] and 'Increment counter' in result['html'],name,result)
    for name in ['find_elements','inspect_element','get_element_state','get_element_attributes','get_element_geometry','get_element_text','get_dom_fragment']:
        cases[name]=lambda c,n=name: read(n)
    def selected(_):
        js("(()=>{const r=document.createRange();r.selectNodeContents(document.querySelector('h1'));const s=getSelection();s.removeAllRanges();s.addRange(r);return true})()")
        check(call('get_selected_text')['text']=='Astra fixture','selected text actual range')
    cases['get_selected_text']=selected
    for name,args in [('wait_for_element',{'selector':'#fixture-click','state':'visible'}),('wait_for_text',{'text':'Astra fixture'}),('wait_for_url',{'url':c['page']}),('wait_for_load_state',{'state':'complete'})]:
        cases[name]=lambda c,n=name,a=args: (call(n,timeout=8,**a),assert_js('document.readyState==="complete"',n+' loaded document'))
    def navigation(_):
        previous=js('location.href')
        call('navigate',url=c['page']+'#wait-navigation')
        call('wait_for_navigation',url=previous,timeout=8)
        assert_js('location.hash==="#wait-navigation"','navigation destination')
    cases['wait_for_navigation']=navigation
    def screenshot(_):
        result=call('screenshot',mode='viewport',format='png')
        data=next(x['data'] for x in result['content'] if x['type']=='image')
        raw=base64.b64decode(data,validate=True)
        check(raw[:8]==b'\x89PNG\r\n\x1a\n','decodable PNG signature')
        width,height=struct.unpack('>II',raw[16:24])
        check(0<width<=100000 and 0<height<=100000,'PNG image dimensions',(width,height))
    cases['screenshot']=screenshot
    cases['evaluate_javascript']=lambda c: assert_js("document.querySelector('h1').textContent==='Astra fixture'",'explicit JS value')
    def inspect(name):
        result=call(name,**({'selector':'#fixture-click'} if name in ['inspect_css','inspect_dom'] else {}))
        if name=='inspect_css': check(result['properties']['display']!='none','computed CSS',result)
        elif name=='inspect_dom': check(any(x['id']=='fixture-click' for x in result['nodes']),'DOM selected node',result)
        elif name=='get_performance_metrics': check(result['domElementCount']>1000,'actual large DOM metric',result)
        else: check(isinstance(result['entries'],list) and any('/state/' in x['name'] for x in result['entries']),'actual fixture network timing',result)
    for name in ['inspect_css','inspect_dom','get_performance_metrics','get_network_requests']:
        cases[name]=lambda c,n=name: inspect(n)
    def console(_):
        call('get_console_messages',enable=True)
        js("console.log('astra-fixture-console-marker')")
        result=call('get_console_messages')
        check(any('astra-fixture-console-marker' in x['message'] for x in result['records']),'recorded console event',result)
    cases['get_console_messages']=console
    def errors(_):
        call('get_javascript_errors',enable=True)
        js("setTimeout(()=>{throw Error('astra-fixture-error-marker')},0)")
        eventually(lambda:any('astra-fixture-error-marker' in x['message'] for x in call('get_javascript_errors')['records']), 'actual asynchronous JS error')
    cases['get_javascript_errors']=errors

    def upload(_):
        ref=call('find_elements',selector='#fixture-file')['elements'][0]['ref']
        result=call('upload_file',ref=ref,scopeToken=c['uploadScope'])
        check(result['status']=='selected','native file selection completed',result)
        eventually(lambda:c['state']().get('upload',{}).get('sha256')==c['uploadSHA256'],'uploaded bytes hash')
        check(c['state']()['files'][0]['name']=='astra-upload-fixture.bin','native selected filename')
    cases['upload_file']=upload

    def selected_page(_):
        selected(c)
        check(call('get_selected_page_text')['text']=='Astra fixture','selected page text')
    cases['get_selected_page_text']=selected_page
    cases['get_page_metadata']=lambda c:check(call('get_page_metadata')['title']=='Astra deterministic MCP fixture','actual page title metadata')
