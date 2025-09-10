class UBHD3DViewerPlugin extends AssetDetail
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
			assetInfo.url = version?.url
			assetInfo.extension = version?.extension
			assetInfo.prio = 5
			return assetInfo

		# PLY-Format
		if version.extension == 'ply' #and version.name == 'preview_version'
			assetInfo.type = 'ply'
			assetInfo.url = version?.url
			assetInfo.extension = version?.extension
			assetInfo.prio = 1
			return assetInfo

		# GLTF-ZIP-Format
		if version.name == 'gltf' and version.class_extension == 'archive.unpack.zip'
			assetInfo.type = 'gltf'
			assetInfo.url = version.versions.directory?.url + '/model.gltf'
			assetInfo.extension = version.versions.original?.extension
			return assetInfo

		# GLB-Format
		if version.extension == 'glb' and version.technical_metadata?.mime_type == 'model/gltf-binary'
			if version?.url? and version?.extension?
				assetInfo.type = 'gltf'
				assetInfo.url = version.url
				assetInfo.extension = version.extension
				assetInfo.prio = 4
				return assetInfo
			else
				console.warn("GLB-Datei ohne gültige URL oder Extension", version)
				return assetInfo

		# RTI-ZIP-Format
		if version.name == 'rti' and version.class_extension == 'archive.unpack.zip'
			assetInfo.type = 'rti'
			assetInfo.url = version.versions.directory?.url
			assetInfo.extension = 'rti'
			return assetInfo

		# 3D Viewer JSON
		if version.original_filename == '3D_viewer.json'
			assetInfo.defaults = version.versions.original?.url
			return assetInfo

		return false

	__easUrl: (asset) ->
		assetInfo =
			type: null
			url: null
			extension: null
			defaults: ''

		return assetInfo unless asset

		variants = if asset instanceof Asset then asset.getSiblingsFromData() else Object.values(asset)
		return assetInfo unless variants

		candidates = []
		for variant in variants
			for version in Object.values(variant.versions)
				assetInfo = @__processVersion(version)
				candidates.push assetInfo if assetInfo.url
				# return assetInfo if @__processVersion(version, assetInfo)

		console.log("__easUrl: assetInfo", assetInfo)
		console.log("__easUrl: candidates", candidates)
		console.log("__easUrl: sortVariants", candidates.sort(sortVariants))

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

	startAutomatically: ->
		true

	#Called by the asset browser to create the html of the viewer.
	createMarkup: ->
		super()
		#We get the info of the asset, url and type
		assetInfo = @__easUrl(@asset)
		if not assetInfo.url and assetInfo.type
			#If we have a type but no url we need to fetch the url from the server using the EAS api
			#this could happen when we get a asset from a linked object standard for example, in that
			#case the server will not send the versions of the asset by default, we have to get it manually.
			ez5.api.eas({
				type: "GET",
				data: {
					ids: JSON.stringify([@asset.value._id]),
					format: "long"
				}
			}).done (assetServerData) =>
				#This call is async so we have to wait the response and then with the data
				# call to __createMarkup
				if assetServerData.error
					return
				@__createMarkup(null, assetServerData)

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

		viewerDiv = CUI.dom.element("div", id: "ubhd3d")
		plugin = ez5.pluginManager.getPlugin("easydb-ubhd-3d-viewer-plugin")
		pluginStaticUrl = plugin.getBaseURL()
		if assetInfo.type == 'nexus' or assetInfo.type == 'ply'
			# 3DHOP-Viewer
			isNexus = 0
			if assetInfo.type == 'nexus'
				isNexus = 1
			iframe = CUI.dom.element("iframe", {
				id: "ubhd3diframe",
				"frameborder": "0",
				"scrolling": "no",
				"src": pluginStaticUrl+"/3dhopiframe.html?nexus="+isNexus+"&asset="+assetInfo.url
			});
		else
			if assetInfo.type == 'rti'
				# relight-Viewer
				iframe = CUI.dom.element("iframe", {
					id: "rtiiframe",
					"frameborder": "0",
					"scrolling": "no",
					"style": "width: 100%; height: 100%;",
					"src": pluginStaticUrl+"/rtiiframe.html?asset="+assetInfo.url
				});
			else
				# three.js-basierter Viewer
				if assetInfo.defaults
					iframe = CUI.dom.element("iframe", {
						id: "threeiframe",
						"frameborder": "0",
						"scrolling": "no",
						"src": pluginStaticUrl+"/threeiframe.html?asset="+assetInfo.url+"."+assetInfo.extension+"&config="+assetInfo.defaults
					});
				else
					iframe = CUI.dom.element("iframe", {
						id: "threeiframe",
						"frameborder": "0",
						"scrolling": "no",
						"src": pluginStaticUrl+"/threeiframe.html?asset="+assetInfo.url+"."+assetInfo.extension
					});

		viewerDiv.appendChild(iframe)
		CUI.dom.append(@outerDiv, viewerDiv)


ez5.session_ready =>
	AssetBrowser.plugins.registerPlugin(UBHD3DViewerPlugin)
	ez5.pluginManager.getPlugin("easydb-ubhd-3d-viewer-plugin").loadCss()
