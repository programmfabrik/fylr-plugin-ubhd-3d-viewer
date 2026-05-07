PLUGIN_ID = 'fylr-plugin-ubhd-3d-viewer'
PLUGIN_SCRIPT_SRC = if typeof document isnt 'undefined' then document.currentScript?.src else null

class UBHD3DViewerPlugin extends AssetDetail
	constructor: (args...) ->
		super(args...)
		@viewerModulePromise = null

	normalizeElement: (target) ->
		return null unless target?
		return target[0] if target.jquery?
		return target.get(0) if typeof target.get is 'function'
		target

	getPluginScript: ->
		return document.currentScript if document.currentScript?.src?

		Array.from(document.scripts).find (script) ->
			/(UBHD3DViewerPlugin(?:\.coffee)?|fylr-plugin-ubhd-3d-viewer)\.js(?:[?#].*)?$/.test(script.src or '')

	normalizePluginBaseUrl: (value) ->
		return null unless value

		try
			url = new URL(value, window.location.href)
			return url.href if /\/$/.test(url.pathname)
			new URL('./', url.href).href
		catch err
			null

	getPluginBaseUrl: ->
		pluginBaseUrl = ez5?.pluginManager?.getPlugin?(PLUGIN_ID)?.getBaseURL?()
		normalized = @normalizePluginBaseUrl(pluginBaseUrl)
		return normalized if normalized?

		normalized = @normalizePluginBaseUrl(PLUGIN_SCRIPT_SRC)
		return normalized if normalized?

		script = @getPluginScript()
		@normalizePluginBaseUrl(script?.src)

	getViewerUrls: ->
		pluginBaseUrl = @getPluginBaseUrl()
		return null unless pluginBaseUrl?

		pageUrl: new URL('viewer-dist/', pluginBaseUrl).href

	ensureViewerStylesheet: (cssUrl) ->
		return unless cssUrl?

		existingLink = document.querySelector("link[data-ubhd-viewer-css='#{cssUrl}']")
		return if existingLink?

		link = document.createElement('link')
		link.rel = 'stylesheet'
		link.href = cssUrl
		link.dataset.ubhdViewerCss = cssUrl
		document.head.appendChild(link)

	importViewerModule: (moduleUrl) ->
		unless @viewerModulePromise?
			@viewerModulePromise = Function('url', 'return import(url)')(moduleUrl)

		@viewerModulePromise

	__probeUrlStatus: (url) ->
		new Promise (resolve) ->
			return resolve(null) unless url

			try
				if window.fetch?
					headOpts = { method: 'HEAD', cache: 'no-store', credentials: 'include' }
					getOpts = { method: 'GET', cache: 'no-store', credentials: 'include', headers: { 'Range': 'bytes=0-0' } }
					fetch(url, headOpts).then((res) ->
						status = res.status
						if status == 405 or status == 501
							fetch(url, getOpts).then((r2) -> resolve(r2.status)).catch((_) -> resolve(null))
						else
							resolve(status)
					).catch((_) ->
						fetch(url, getOpts).then((r2) -> resolve(r2.status)).catch((__) -> resolve(null))
					)
					return

				if window.$?.ajax?
					$.ajax({ url: url, type: 'HEAD', cache: false, xhrFields: { withCredentials: true } }).done((_) ->
						resolve(200)
					).fail((xhr, _status, _err) ->
						resolve(xhr?.status ? null)
					)
					return
			catch err
				# ignore

			resolve(null)

	__pickFirstAccessible: (assetInfos) ->
		new Promise (resolve) =>
			candidates = (assetInfos or []).filter((assetInfo) -> assetInfo?.url)
			return resolve(null) unless candidates.length

			unknown = []
			idx = 0

			checkNext = =>
				return resolve(unknown[0] ? null) if idx >= candidates.length

				candidate = candidates[idx]
				idx += 1

				@__probeUrlStatus(candidate.url).then((status) =>
					if typeof status == 'number' and status >= 200 and status < 400
						resolve(candidate)
					else if status in [403, 404, 0]
						checkNext()
					else if status?
						checkNext()
					else
						unknown.push(candidate)
						checkNext()
				).catch((_) =>
					unknown.push(candidate)
					checkNext()
				)

			checkNext()

	__bestVersionUrl: (version) ->
		return null unless version?
		return version.url if version.url?
		return version.versions?.original?.url if version.versions?.original?.url?
		null

	__sameOriginUrl: (rawUrl) ->
		return rawUrl unless rawUrl

		try
			u = new URL(rawUrl, window.location.href)
			if u.origin isnt window.location.origin
				return u.pathname + u.search + u.hash
			return u.href
		catch err
			rawUrl

	__withAccessToken: (rawUrl) ->
		return rawUrl unless rawUrl

		token = ez5?.session?.token
		return rawUrl unless token

		try
			u = new URL(rawUrl, window.location.href)
			isApiUrl = u.origin == window.location.origin and u.pathname.indexOf('/api/') == 0
			return rawUrl unless isApiUrl
			unless u.searchParams.get('access_token')
				u.searchParams.set('access_token', token)
			return u.pathname + u.search + u.hash
		catch err
			separator = if rawUrl.indexOf('?') == -1 then '?' else '&'
			rawUrl + separator + 'access_token=' + encodeURIComponent(token)

	__processVersion: (version) ->
		assetInfo =
			type: null
			url: null
			extension: null
			prio: null
			defaults: ''

		return false unless version?

		if version.name == 'gltf' and version.class_extension == 'archive.unpack.zip'
			assetInfo.type = 'gltf'
			assetInfo.prio = 5
			assetInfo.url = version.versions?.directory?.url + '/model.gltf'
			assetInfo.extension = version.versions?.original?.extension
			return assetInfo if assetInfo.url?

		if version.extension == 'glb'
			url = @__bestVersionUrl(version)
			if url?
				assetInfo.type = 'gltf'
				assetInfo.url = url
				assetInfo.extension = version.extension
				assetInfo.prio = 5
				return assetInfo

		if version.extension == 'gltf'
			url = @__bestVersionUrl(version)
			if url?
				assetInfo.type = 'gltf'
				assetInfo.url = url
				assetInfo.extension = version.extension
				assetInfo.prio = 4
				return assetInfo

		false

	__easUrl: (asset) ->
		assetInfo =
			type: null
			url: null
			extension: null
			defaults: ''
			alternatives: []

		return assetInfo unless asset

		variants = if asset instanceof Asset then asset.getSiblingsFromData() else Object.values(asset)
		return assetInfo unless variants

		candidates = []
		defaults = null
		hasTypeWithoutUrl = false

		for variant in variants
			for version in Object.values(variant.versions or {})
				if version.original_filename == '3D_viewer.json'
					defaults = version.versions?.original?.url
				else
					processed = @__processVersion(version)
					if processed and processed.type and not processed.url
						hasTypeWithoutUrl = true
					candidates.push(processed) if processed and processed.url

		if candidates.length > 0
			sorted = candidates.sort(sortVariants)
			assetInfo = sorted[0]
			assetInfo.defaults = defaults if defaults
			assetInfo.alternatives = sorted.slice(1)
			for alternative in assetInfo.alternatives
				alternative.defaults = defaults if defaults
			return assetInfo

		if hasTypeWithoutUrl
			assetInfo.type = 'pending'
			assetInfo.defaults = defaults if defaults

		assetInfo

	getButtonLocaKey: (asset) ->
		assetInfo = @__easUrl(asset ? @asset)
		assetInfo = @fallbackAssetInfo(asset ? @asset) unless assetInfo.url or assetInfo.type
		return unless assetInfo.url or assetInfo.type
		'ubhd.asset.detail.360degrees'

	__fetchFullAssetInfo: ->
		assetId = @asset?.value?._id
		return null unless assetId

		ez5.api.eas(
			type: 'GET'
			data:
				ids: JSON.stringify([assetId])
				format: 'long'
		)

	startAutomatically: ->
		true

	getExtension: (url) ->
		return null unless typeof url is 'string'

		match = url.toLowerCase().match(/\.([a-z0-9]+)(?:$|[?#])/) 
		if match then match[1] else null

	collectModelUrlCandidates: (value, seen = new WeakSet(), depth = 0, path = [], results = []) ->
		return results if depth > 7 or not value?

		if typeof value is 'string'
			extension = @getExtension(value)
			if extension in ['glb', 'gltf']
				results.push(
					url: value
					extension: extension
					path: path.slice()
				)
			return results

		return results unless typeof value is 'object'
		return results if seen.has(value)
		seen.add(value)

		if Array.isArray(value)
			value.forEach (item, index) =>
				@collectModelUrlCandidates(item, seen, depth + 1, path.concat(["#{index}"]), results)
			return results

		Object.entries(value).forEach ([key, nestedValue]) =>
			@collectModelUrlCandidates(nestedValue, seen, depth + 1, path.concat([key]), results)

		results

	scoreModelCandidate: (candidate) ->
		pathText = candidate.path.join('.').toLowerCase()
		score = if candidate.extension == 'glb' then 120 else 110

		score += 40 if /(^|\.)(url|href|download|downloadurl|file|original|source|target)$/.test(pathText)
		score += 20 if /(version|versions|derived|files|asset|original|source)/.test(pathText)
		score -= 120 if /(preview|poster|thumbnail|thumb|icon|logo|image)/.test(pathText)

		score

	fallbackAssetInfo: (asset) ->
		source = asset?.value ? asset
		candidates = @collectModelUrlCandidates(source)
		return null unless candidates.length

		bestCandidate = candidates
			.map((candidate) =>
				Object.assign({}, candidate, score: @scoreModelCandidate(candidate))
			)
			.sort((left, right) -> right.score - left.score)[0]

		return null unless bestCandidate?.url

		type: 'gltf'
		url: bestCandidate.url
		extension: bestCandidate.extension
		prio: if bestCandidate.extension == 'glb' then 5 else 4
		defaults: ''
		alternatives: []

	createViewerContainer: (target) ->
		container = @normalizeElement(target)
		return null unless container?

		container.innerHTML = ''
		container.style.minHeight = '480px'

		canvas = document.createElement('canvas')
		canvas.className = 'webgl'
		container.appendChild(canvas)

		container: container
		canvas: canvas

	__mountViewer: (target, assetInfo) ->
		urls = @getViewerUrls()

		unless urls?.pageUrl?
			console.error('[UBHD3DViewerPlugin] Unable to determine viewer asset URLs.')
			return Promise.resolve(null)

		container = @normalizeElement(target)
		return Promise.resolve(null) unless container?
		container.innerHTML = ''
		container.style.minHeight = '480px'

		iframe = document.createElement('iframe')
		iframe.id = 'threeiframe'
		iframe.setAttribute('frameborder', '0')
		iframe.setAttribute('scrolling', 'no')
		iframe.style.width = '100%'
		iframe.style.minHeight = '480px'
		iframe.style.border = '0'

		pageUrl = new URL(urls.pageUrl)
		pageUrl.searchParams.set('asset', assetInfo?.url or '')
		pageUrl.searchParams.set('config', assetInfo.defaults) if assetInfo?.defaults
		iframe.src = pageUrl.href

		container.appendChild(iframe)
		Promise.resolve(iframe)

	createMarkup: ->
		super()
		assetInfo = @__easUrl(@asset)
		assetInfo = @fallbackAssetInfo(@asset) unless assetInfo.url or assetInfo.type
		request = @__fetchFullAssetInfo()

		if request?
			request.done (assetServerData) =>
				if assetServerData?.error
					@__createMarkup(assetInfo) if assetInfo.url
					return
				@__createMarkup(null, assetServerData)
			.fail =>
				@__createMarkup(assetInfo) if assetInfo.url
			return

		return if not assetInfo.url and assetInfo.type
		@__createMarkup(assetInfo) if assetInfo.url
		return

	__createMarkup: (assetInfo, assetServerData) ->
		if not assetInfo and assetServerData
			assetInfo = @__easUrl(assetServerData)
			assetInfo = @fallbackAssetInfo(assetServerData) unless assetInfo?.url and assetInfo?.type
			return unless assetInfo?.url and assetInfo?.type

		assetInfo.url = @__sameOriginUrl(assetInfo.url)
		assetInfo.url = @__withAccessToken(assetInfo.url)
		assetInfo.defaults = @__sameOriginUrl(assetInfo.defaults) if assetInfo.defaults
		assetInfo.defaults = @__withAccessToken(assetInfo.defaults) if assetInfo.defaults
		assetInfo.alternatives = (assetInfo.alternatives or []).map((alternative) =>
			return alternative unless alternative?.url
			alternative.url = @__sameOriginUrl(alternative.url)
			alternative.url = @__withAccessToken(alternative.url)
			alternative.defaults = @__sameOriginUrl(alternative.defaults) if alternative.defaults
			alternative.defaults = @__withAccessToken(alternative.defaults) if alternative.defaults
			alternative
		)

		viewerDiv = CUI.dom.element('div', id: 'ubhd3d')
		CUI.dom.append(@outerDiv, viewerDiv)

		allCandidates = [assetInfo].concat(assetInfo.alternatives or [])
		@__pickFirstAccessible(allCandidates).then((chosen) =>
			unless chosen
				viewerDiv.textContent = '3D-Datei kann mit den aktuellen Rechten nicht geladen werden.'
				return

			@__mountViewer(viewerDiv, chosen).catch((error) =>
				console.error('[UBHD3DViewerPlugin] Failed to mount embedded viewer.', error)
				viewerDiv.textContent = '3D-Datei kann derzeit nicht geladen werden.'
			)
		).catch((_) =>
			viewerDiv.textContent = '3D-Datei kann derzeit nicht geladen werden.'
		)

		return

window.UBHD3DViewerPlugin = UBHD3DViewerPlugin if typeof window isnt 'undefined'

sortVariants = (a, b) ->
	if a.prio and b.prio
		b.prio - a.prio
	else if a.prio
		-1
	else if b.prio
		1
	else
		0

ez5.session_ready =>
	AssetBrowser?.plugins?.registerPlugin?(UBHD3DViewerPlugin)
	ez5.pluginManager.getPlugin('fylr-plugin-ubhd-3d-viewer')?.loadCss?()