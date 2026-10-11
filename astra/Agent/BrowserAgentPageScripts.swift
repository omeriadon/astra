#if os(macOS) && !ASTRA_WEBSITE_APP_HELPER
	import Foundation

	enum BrowserAgentPageScripts {
		static let snapshot = #"""
		const visible = node => {
		    const style = getComputedStyle(node);
		    const rect = node.getBoundingClientRect();
		    return node.isConnected && !node.hidden && style.display !== 'none'
		        && style.visibility === 'visible' && Number(style.opacity) !== 0
		        && rect.width > 0 && rect.height > 0;
		};
		const nodes = new Map();
		const controls = [];
		let truncated = false;
		function walk(root) {
		    for (const node of root.querySelectorAll('*')) {
		        if (controls.length >= 300) { truncated = true; return; }
		        if (node.shadowRoot) walk(node.shadowRoot);
		        if (!node.matches('a[href],button,input,textarea,select,[role],h1,h2,h3') || !visible(node)) continue;
		        if (node.matches('input[type=password],input[type=hidden],input[type=file]')) continue;
		        const ref = snapshotID + ':' + controls.length;
		        nodes.set(ref, new WeakRef(node));
		        const role = node.getAttribute('role') || ({A:'link',BUTTON:'button',INPUT:'textbox',TEXTAREA:'textbox',SELECT:'combobox'})[node.tagName] || node.tagName.toLowerCase();
		        const labels = node.labels ? Array.from(node.labels).map(label => label.innerText).join(' ') : '';
		        const name = node.getAttribute('aria-label') || labels || node.innerText || node.getAttribute('title') || node.getAttribute('placeholder') || '';
		        controls.push({ref, role, name: name.trim().slice(0, 500), disabled: !!node.disabled});
		    }
		}
		walk(document);
		globalThis.__astraBrowserUse = {snapshotID, nodes, visible};
		return {title: document.title, url: location.href, controls, truncated, frameSupport: 'main frame and open shadow roots'};
		"""#

		static let action = #"""
		if (operation === 'scroll') {
		    window.scrollBy({top: dy, behavior: 'instant'});
		    return {ok: true};
		}
		const state = globalThis.__astraBrowserUse;
		const node = state?.snapshotID === snapshotID ? state.nodes.get(ref)?.deref() : null;
		if (!node || !state.visible(node) || node.disabled || node.getAttribute('aria-disabled') === 'true') throw new Error('Stale or unavailable element; take another snapshot.');
		if (operation === 'click') {
		    node.scrollIntoView({block: 'center', inline: 'center', behavior: 'instant'});
		    const rect = node.getBoundingClientRect();
		    const root = node.getRootNode();
		    const target = root.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
		    if (!target || !(target === node || node.contains(target))) throw new Error('Element is obscured.');
		    node.click();
		} else if (operation === 'fill') {
		    if (!node.matches('input,textarea') || node.readOnly || node.matches('input[type=password],input[type=file],input[type=hidden],input[type=checkbox],input[type=radio],input[type=submit],input[type=button],input[type=reset],input[type=image]')) throw new Error('Element is not an editable text field.');
		    node.focus();
		    const prototype = node.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
		    Object.getOwnPropertyDescriptor(prototype, 'value').set.call(node, value);
		    node.dispatchEvent(new Event('input', {bubbles: true, composed: true}));
		    node.dispatchEvent(new Event('change', {bubbles: true}));
		} else if (operation === 'select_option') {
		    if (node.tagName !== 'SELECT' || !Array.from(node.options).some(option => option.value === value && !option.disabled)) throw new Error('Available select option required.');
		    node.value = value;
		    node.dispatchEvent(new Event('input', {bubbles: true}));
		    node.dispatchEvent(new Event('change', {bubbles: true}));
		}
		return {ok: true};
		"""#
	}
#endif
