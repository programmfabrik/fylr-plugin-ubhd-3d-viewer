class UBHD3DViewerPlugin extends AssetDetail
	__probeUrlStatus: (url) ->
		new Promise (resolve) ->
			return resolve(null) unless url
			try
				if window.fetch?
					headOpts = { method: 'HEAD', cache: 'no-store', credentials: 'include' }
					getOpts = { method: 'GET', cache: 'no-store', credentials: 'include', headers: { 'Range': 'bytes=0-0' } }
					fetch(url, headOpts).then((res) ->
						status = res.status
						# If HEAD is not allowed/usable, retry with a minimal GET.
						if status == 405 or status == 501
							fetch(url, getOpts).then((r2) -> resolve(r2.status)).catch((_) -> resolve(null))
						else
							resolve(status)
					).catch((_) ->
						# Some endpoints may not allow HEAD; retry with minimal GET.
						fetch(url, getOpts).then((r2) -> resolve(r2.status)).catch((__) -> resolve(null))
					)
					return
				if window.$?.ajax?
					$.ajax({ url: url, type: 'HEAD', cache: false, xhrFields: { withCredentials: true } }).done((_) ->
						resolve(200)
					).fail((xhr, _status, _err) ->
						st = xhr?.status ? null
						# jQuery cannot set Range easily for HEAD fallback here; return unknown.
						resolve(st)
					)
					return
			catch err
				# ignore
			resolve(null)

	__pickFirstAccessible: (assetInfos) ->
		new Promise (resolve) =>
			candidates = (assetInfos or []).filter((x) -> x?.url)
			return resolve(null) unless candidates.length
			unknown = []

			idx = 0
			checkNext = =>
				# If every known candidate is forbidden or missing, do not retry the first one.
				if idx >= candidates.length
					return resolve(unknown[0] ? null)
				candidate = candidates[idx]
				idx += 1
				@__probeUrlStatus(candidate.url).then((status) =>
					if typeof status == 'number' and status >= 200 and status < 400
						resolve(candidate)
					else if status == 403
						checkNext()
					else if status == 404
						checkNext()
					else if status == 0
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
		return null unless version
		return version?.url if version?.url
		return version.versions?.original?.url if version.versions?.original?.url
		return null

	__sameOriginUrl: (rawUrl) ->
		return rawUrl unless rawUrl
		try
			u = new URL(rawUrl, window.location.href)
			if u.origin != window.location.origin
				return u.pathname + u.search + u.hash
			return u.href
		catch err
			return rawUrl

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
			return rawUrl + separator + 'access_token=' + encodeURIComponent(token)

	__processVersion: (version) ->		
		# Nexus-Format
		assetInfo = 
			type: null
			url: null
			extension: null
			prio: null
			defaults: ''
		
		if version.extension in ['nxs', 'nxz']
			assetInfo.type = 'nexus'
			assetInfo.url = @__bestVersionUrl(version)
			assetInfo.extension = version?.extension
			assetInfo.prio = 4
			return assetInfo

		# PLY-Format
		if version.extension == 'ply' #and version.name == 'preview_version'
			assetInfo.type = 'ply'
			assetInfo.url = @__bestVersionUrl(version)
			assetInfo.extension = version?.extension
			assetInfo.prio = 1
			return assetInfo

		# GLTF-ZIP-Format
		if version.name == 'gltf' and version.class_extension == 'archive.unpack.zip'
			assetInfo.type = 'gltf'
			assetInfo.prio = 5
			assetInfo.url = version.versions.directory?.url + '/model.gltf'
			assetInfo.extension = version.versions.original?.extension
			return assetInfo

		# OBJ-Format (Fallback, falls abgeleitete GLBs nicht zugreifbar sind)
		if version.extension == 'obj'
			url = @__bestVersionUrl(version)
			if url?
				assetInfo.type = 'obj'
				assetInfo.url = url
				assetInfo.extension = version.extension
				assetInfo.prio = 2
				return assetInfo

		# GLB-Format
		if (version.extension == 'glb' or version.extension == 'gltf') and version.technical_metadata?.mime_type == 'model/gltf-binary'
			url = @__bestVersionUrl(version)
			if url? and version?.extension?
				assetInfo.type = 'gltf'
				assetInfo.url = url
				assetInfo.extension = version.extension
				if version.extension == 'glb'
					assetInfo.prio = 5
				else if version.extension == 'gltf'
					assetInfo.prio = 3
				return assetInfo
			else
				console.warn("GLB-Datei ohne gültige URL oder Extension", version)
				return assetInfo

		# RTI-ZIP-Format
		if version.name == 'rti' and version.class_extension == 'archive.unpack.zip'
			assetInfo.type = 'rti'
			assetInfo.prio = 5
			assetInfo.url = version.versions.directory?.url
			assetInfo.extension = 'rti'
			return assetInfo

		return false

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
			# an asset that is still uploading or producing has no versions yet
			for version in Object.values(variant?.versions or {})
			# 3D Viewer JSON
				if version.original_filename == '3D_viewer.json'
					defaults = version.versions.original?.url
				else 		
					assetInfo = @__processVersion(version)
					if assetInfo and assetInfo.type and not assetInfo.url
						hasTypeWithoutUrl = true
					candidates.push assetInfo if assetInfo and assetInfo.url

		console.log("__easUrl: assetInfo", assetInfo)
		console.log("__easUrl: candidates", candidates)
		console.log("__easUrl: sortVariants", candidates.sort(sortVariants))

		if candidates.length > 0
			sorted = candidates.sort(sortVariants)
			if sorted.some((candidate) -> candidate?.type == 'gltf')
				sorted = sorted.filter((candidate) -> candidate?.type != 'obj')
			assetInfo = sorted[0]
			assetInfo.defaults = defaults if defaults
			assetInfo.alternatives = sorted.slice(1)
			for alt in assetInfo.alternatives
				alt.defaults = defaults if defaults
			console.log("__easUrl: selected assetInfo", assetInfo)
			return assetInfo
		else if hasTypeWithoutUrl
			# Trigger server fetch (format=long) in createMarkup
			assetInfo.type = 'pending'
			assetInfo.defaults = defaults if defaults
		return assetInfo

	sortVariants = (a, b) ->
		if a.prio and b.prio
			return b.prio - a.prio
		else if a.prio
			return -1
		else if b.prio
			return 1
		else
			return 0

	getButtonLocaKey: (asset) ->
		assetInfo = @__easUrl(asset)
		if not assetInfo.url and not assetInfo.type
			return

		return "ubhd.asset.detail.360degrees"

	__fetchFullAssetInfo: ->
		assetId = @asset?.value?._id
		return null unless assetId
		ez5.api.eas({
			type: "GET",
			data: {
				ids: JSON.stringify([assetId]),
				format: "long"
			}
		})

	startAutomatically: ->
		true

	#Called by the asset browser to create the html of the viewer.
	createMarkup: ->
		super()
		#We get the info of the asset, url and type
		assetInfo = @__easUrl(@asset)
		request = @__fetchFullAssetInfo()

		if request?
			# The upload/detail context may only expose a reduced variant set.
			# Fetch the long EAS payload so we can see original + derived alternatives
			# and fall back from a rights-protected GLB to OBJ/NXZ when needed.
			request.done (assetServerData) =>
				if assetServerData?.error
					@__createMarkup(assetInfo) if assetInfo.url
					return
				@__createMarkup(null, assetServerData)
			.fail =>
				@__createMarkup(assetInfo) if assetInfo.url
			return

		if not assetInfo.url and assetInfo.type
			return

		#If we have url we can create the html.
		if assetInfo.url
			@__createMarkup(assetInfo)

		return

	#This private method is used to be able to call async the create markup behaviour.
	__createMarkup: (assetInfo, assetServerData) ->
		#If we have serverData we get the asset info using __easUrl()
		if not assetInfo and assetServerData
			assetInfo = @__easUrl(assetServerData)
			if not assetInfo or not assetInfo.url or not assetInfo.type
				return

		# Wichtig: URLs können absolute Hosts enthalten (z.B. Prod-Hostname),
		# während der Benutzer über einen anderen Host zugreift.
		# In dem Fall wären Fetch/XHR im IFrame cross-origin und würden keine
		# Session-Cookies mitsenden (=> 403). Daher auf Same-Origin-Pfad normalisieren.
		assetInfo.url = @__sameOriginUrl(assetInfo.url)
		assetInfo.url = @__withAccessToken(assetInfo.url)
		assetInfo.defaults = @__sameOriginUrl(assetInfo.defaults) if assetInfo.defaults
		assetInfo.defaults = @__withAccessToken(assetInfo.defaults) if assetInfo.defaults
		assetInfo.alternatives = (assetInfo.alternatives or []).map((a) =>
			return a unless a?.url
			a.url = @__sameOriginUrl(a.url)
			a.url = @__withAccessToken(a.url)
			a.defaults = @__sameOriginUrl(a.defaults) if a.defaults
			a.defaults = @__withAccessToken(a.defaults) if a.defaults
			return a
		)

		viewerDiv = CUI.dom.element("div", id: "ubhd3d")
		plugin = ez5.pluginManager.getPlugin("fylr-plugin-ubhd-3d-viewer")
		pluginStaticUrl = plugin.getBaseURL()

		# Append container early; set iframe src once we've picked an accessible candidate
		CUI.dom.append(@outerDiv, viewerDiv)
		iframe = CUI.dom.element("iframe", {
			id: "ubhd3diframe",
			"frameborder": "0",
			"scrolling": "no",
			"src": "about:blank"
		})
		viewerDiv.appendChild(iframe)

		allCandidates = [assetInfo].concat(assetInfo.alternatives or [])
		@__pickFirstAccessible(allCandidates).then((chosen) =>
			unless chosen
				viewerDiv.textContent = '3D-Datei kann mit den aktuellen Rechten nicht geladen werden.'
				return
			if chosen.type == 'nexus' or chosen.type == 'ply'
				isNexus = if chosen.type == 'nexus' then 1 else 0
				assetParam = encodeURIComponent(chosen.url)
				iframe.setAttribute('src', pluginStaticUrl+"/3dhopiframe.html?nexus="+isNexus+"&asset="+assetParam)
			else if chosen.type == 'rti'
				iframe.setAttribute('id', 'rtiiframe')
				iframe.setAttribute('style', 'width: 100%; height: 100%;')
				iframe.setAttribute('src', pluginStaticUrl+"/rtiiframe.html?asset="+encodeURIComponent(chosen.url))
			else
				if chosen.defaults
					iframe.setAttribute('id', 'threeiframe')
					iframe.setAttribute('src', pluginStaticUrl+"/threeiframe.html?asset="+encodeURIComponent(chosen.url)+"&config="+encodeURIComponent(chosen.defaults))
				else
					iframe.setAttribute('id', 'threeiframe')
					iframe.setAttribute('src', pluginStaticUrl+"/threeiframe.html?asset="+encodeURIComponent(chosen.url))
		).catch((_) =>
			viewerDiv.textContent = '3D-Datei kann derzeit nicht geladen werden.'
		)

		return


ez5.session_ready =>
	AssetBrowser.plugins.registerPlugin(UBHD3DViewerPlugin)
	# fylr answers /api/v1/plugin with a 30 day cache header, so the plugin list
	# the frontend booted with can be older than the bundle this code comes in
	ez5.pluginManager.getPlugin("fylr-plugin-ubhd-3d-viewer")?.loadCss()
