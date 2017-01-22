-- Lightroom SDK
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrView = import 'LrView'

local logger = import 'LrLogger'( 'GPhotoAPI' )
logger:enable('logfile')

-- Common shortcuts
local bind = LrView.bind
local share = LrView.share

-- GPhoto plug-in
require 'GPhotoAPI'
require 'GPhotoPublishSupport'

--------------------------------------------------------------------------------

local exportServiceProvider = {}

-- publish specific hooks are in another file
for name, value in pairs( GPhotoPublishSupport ) do
	exportServiceProvider[ name ] = value
end

local function dumpTable(t)
	for k,v in pairs(t) do
		logger:info(k, type(v), v)
		if type(v) == 'table' then
			for k2,v2 in pairs(v) do
				logger:info(k .. '>' .. k2, type(v2), v2)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- support only publish
-- TODO: support export
exportServiceProvider.supportsIncrementalPublish = 'only'

exportServiceProvider.exportPresetFields = {
	{ key = 'access_token', default = '' },
	{ key = 'refresh_token', default = '' },
}

--- photos are always rendered to a temporary location and are deleted when the export is complete
exportServiceProvider.hideSections = { 'exportLocation' }

exportServiceProvider.allowFileFormats = { 'JPEG' }
exportServiceProvider.allowColorSpaces = { 'sRGB' }

-- recommended when exporting to the web
exportServiceProvider.hidePrintResolution = true

-- TODO: should be true
exportServiceProvider.canExportVideo = false -- video is not supported through this sample plug-in

--------------------------------------------------------------------------------
-- Google Photo SPECIFIC: Helper functions and tables.

local function updateCantExportBecause( propertyTable )
	if not propertyTable.validAccount then
		propertyTable.LR_cantExportBecause = LOC "$$$/GPhoto/ExportDialog/NoLogin=You haven't logged in to Google Photo yet."
		return
	end
	propertyTable.LR_cantExportBecause = nil
end

local displayNameForTitleChoice = {
	filename = LOC "$$$/GPhoto/ExportDialog/Title/Filename=Filename",
	title = LOC "$$$/GPhoto/ExportDialog/Title/Title=IPTC Title",
	empty = LOC "$$$/GPhoto/ExportDialog/Title/Empty=Leave Blank",
}

local kSafetyTitles = {
	safe = LOC "$$$/GPhoto/ExportDialog/Safety/Safe=Safe",
	moderate = LOC "$$$/GPhoto/ExportDialog/Safety/Moderate=Moderate",
	restricted = LOC "$$$/GPhoto/ExportDialog/Safety/Restricted=Restricted",
}

local function booleanToNumber( value )
	return value and 1 or 0
end

local function getGPhotoTitle( photo, exportSettings, pathOrMessage )
	local title

	-- Get title according to the options in GPhoto Title section.
	if exportSettings.titleFirstChoice == 'filename' then
		title = LrPathUtils.leafName( pathOrMessage )
	elseif exportSettings.titleFirstChoice == 'title' then
		title = photo:getFormattedMetadata 'title'
		if ( not title or #title == 0 ) and exportSettings.titleSecondChoice == 'filename' then
			title = LrPathUtils.leafName( pathOrMessage )
		end
	end
	return title
end

--------------------------------------------------------------------------------
function exportServiceProvider.startDialog( propertyTable )
	logger:trace('startDialog')

	-- Clear login if it's a new connection.
	logger:info("Existing access_token: '" .. propertyTable.access_token .. "'")
	--propertyTable.access_token = 'ya29.Ci_UA7aEsvT6-oVI8fjxZvB6i8oO13WgdZUviLaCVtpEPYZqhQcQycR-u2X9xtmYGA'
	if not propertyTable.LR_editingExistingPublishConnection then
		propertyTable.username = nil
		propertyTable.nsid = nil
		propertyTable.auth_token = nil
	end

	-- Can't export until we've validated the login.
	propertyTable:addObserver( 'validAccount', function() updateCantExportBecause( propertyTable ) end )
	updateCantExportBecause( propertyTable )

	-- Make sure we're logged in.
	require 'GPhotoUser'
	GPhotoUser.verifyLogin( propertyTable )
end


--------------------------------------------------------------------------------

function exportServiceProvider.sectionsForTopOfDialog( f, propertyTable )
	return {
		{
			title = LOC "$$$/GPhoto/ExportDialog/Account=Google Photo Account",
			synopsis = bind 'accountStatus',

			f:row {
				spacing = f:control_spacing(),

				f:static_text {
					title = bind 'accountStatus',
					alignment = 'right',
					fill_horizontal = 1,
				},

				f:push_button {
					width = tonumber( LOC "$$$/locale_metric/GPhoto/ExportDialog/LoginButton/Width=90" ),
					title = bind 'loginButtonTitle',
					enabled = bind 'loginButtonEnabled',
					action = function()
					require 'GPhotoUser'
					GPhotoUser.login( propertyTable )
					end,
				},

				f:push_button {
					width = tonumber( LOC "$$$/locale_metric/GPhoto/ExportDialog/ChangeAccountButton/Width=90" ),
					title = bind 'changeAccountButtonTitle',
					enabled = bind 'changeAccountButtonEnabled',
					action = function()
						require 'GPhotoUser'
						GPhotoUser.changeAccount( propertyTable )
					end,
				},

				f:push_button {
					width = tonumber( LOC "$$$/locale_metric/GPhoto/ExportDialog/RevokeAccountButton/Width=90" ),
					title = bind 'revokeAccountButtonTitle',
					enabled = bind 'revokeAccountEnabled',
					action = function()
						require 'GPhotoUser'
						GPhotoUser.revokeAccount( propertyTable )
					end,
				},
			},
		},

		{
			title = LOC "$$$/GPhoto/ExportDialog/Title=GPhoto Title",

			synopsis = function( props )
				if props.titleFirstChoice == 'title' then
					return LOC( "$$$/GPhoto/ExportDialog/Synopsis/TitleWithFallback=IPTC Title or ^1", displayNameForTitleChoice[ props.titleSecondChoice ] )
				else
					return props.titleFirstChoice and displayNameForTitleChoice[ props.titleFirstChoice ] or ''
				end
			end,

			f:column {
				spacing = f:control_spacing(),

				f:row {
					spacing = f:label_spacing(),

					f:static_text {
						title = LOC "$$$/GPhoto/ExportDialog/ChooseTitleBy=Set GPhoto Title Using:",
						alignment = 'right',
						width = share 'GPhotoTitleSectionLabel',
					},

					f:popup_menu {
						value = bind 'titleFirstChoice',
						width = share 'GPhotoTitleLeftPopup',
						items = {
							{ value = 'filename', title = displayNameForTitleChoice.filename },
							{ value = 'title', title = displayNameForTitleChoice.title },
							{ value = 'empty', title = displayNameForTitleChoice.empty },
						},
					},

					f:spacer { width = 20 },

					f:static_text {
						title = LOC "$$$/GPhoto/ExportDialog/ChooseTitleBySecondChoice=If Empty, Use:",
						enabled = LrBinding.keyEquals( 'titleFirstChoice', 'title', propertyTable ),
					},

					f:popup_menu {
						value = bind 'titleSecondChoice',
						enabled = LrBinding.keyEquals( 'titleFirstChoice', 'title', propertyTable ),
						items = {
							{ value = 'filename', title = displayNameForTitleChoice.filename },
							{ value = 'empty', title = displayNameForTitleChoice.empty },
						},
					},
				},

				f:row {
					spacing = f:label_spacing(),

					f:static_text {
						title = LOC "$$$/GPhoto/ExportDialog/OnUpdate=When Updating Photos:",
						alignment = 'right',
						width = share 'GPhotoTitleSectionLabel',
					},

					f:popup_menu {
						value = bind 'titleRepublishBehavior',
						width = share 'GPhotoTitleLeftPopup',
						items = {
							{ value = 'replace', title = LOC "$$$/GPhoto/ExportDialog/ReplaceExistingTitle=Replace Existing Title" },
							{ value = 'leaveAsIs', title = LOC "$$$/GPhoto/ExportDialog/LeaveAsIs=Leave Existing Title" },
						},
					},
				},
			},
		},
	}
end

--------------------------------------------------------------------------------
function exportServiceProvider.sectionsForBottomOfDialog( f, propertyTable )
	return {
		{
			title = LOC "$$$/GPhoto/ExportDialog/PrivacyAndSafety=Privacy and Safety",
			synopsis = function( props )
				local summary = {}

				local function add( x )
					if x then
						summary[ #summary + 1 ] = x
					end
				end

				if props.privacy == 'private' then
					add( LOC "$$$/GPhoto/ExportDialog/Private=Private" )
					if props.privacy_family then
						add( LOC "$$$/GPhoto/ExportDialog/Family=Family" )
					end
					if props.privacy_friends then
						add( LOC "$$$/GPhoto/ExportDialog/Friends=Friends" )
					end
				else
					add( LOC "$$$/GPhoto/ExportDialog/Public=Public" )
				end

				local safetyStr = kSafetyTitles[ props.safety ]
				if safetyStr then
					add( safetyStr )
				end
				return table.concat( summary, " / " )
			end,

			place = 'horizontal',

			f:column {
				spacing = f:control_spacing() / 2,
				fill_horizontal = 1,

				f:row {
					f:static_text {
						title = LOC "$$$/GPhoto/ExportDialog/Privacy=Privacy:",
						alignment = 'right',
						width = share 'labelWidth',
					},

					f:radio_button {
						title = LOC "$$$/GPhoto/ExportDialog/Private=Private",
						checked_value = 'private',
						value = bind 'privacy',
					},
				},

				f:row {
					f:spacer {
						width = share 'labelWidth',
					},

					f:column {
						spacing = f:control_spacing() / 2,
						margin_left = 15,
						margin_bottom = f:control_spacing() / 2,

						f:checkbox {
							title = LOC "$$$/GPhoto/ExportDialog/Family=Family",
							value = bind 'privacy_family',
							enabled = LrBinding.keyEquals( 'privacy', 'private' ),
						},

						f:checkbox {
							title = LOC "$$$/GPhoto/ExportDialog/Friends=Friends",
							value = bind 'privacy_friends',
							enabled = LrBinding.keyEquals( 'privacy', 'private' ),
						},
					},
				},

				f:row {
					f:spacer {
						width = share 'labelWidth',
					},

					f:radio_button {
						title = LOC "$$$/GPhoto/ExportDialog/Public=Public",
						checked_value = 'public',
						value = bind 'privacy',
					},
				},
			},

			f:column {
				spacing = f:control_spacing() / 2,

				fill_horizontal = 1,

				f:row {
					f:static_text {
						title = LOC "$$$/GPhoto/ExportDialog/Safety=Safety:",
						alignment = 'right',
						width = share 'GPhoto_col2_label_width',
					},

					f:popup_menu {
						value = bind 'safety',
						width = share 'GPhoto_col2_popup_width',
						items = {
							{ title = kSafetyTitles.safe, value = 'safe' },
							{ title = kSafetyTitles.moderate, value = 'moderate' },
							{ title = kSafetyTitles.restricted, value = 'restricted' },
						},
					},
				},

				f:row {
					margin_bottom = f:control_spacing() / 2,

					f:spacer {
						width = share 'GPhoto_col2_label_width',
					},

					f:checkbox {
						title = LOC "$$$/GPhoto/ExportDialog/HideFromPublicSite=Hide from public site areas",
						value = bind 'hideFromPublic',
					},
				},

				f:row {
					f:static_text {
						title = LOC "$$$/GPhoto/ExportDialog/Type=Type:",
						alignment = 'right',
						width = share 'GPhoto_col2_label_width',
					},

					f:popup_menu {
						width = share 'GPhoto_col2_popup_width',
						value = bind 'type',
						items = {
							{ title = LOC "$$$/GPhoto/ExportDialog/Type/Photo=Photo", value = 'photo' },
							{ title = LOC "$$$/GPhoto/ExportDialog/Type/Screenshot=Screenshot", value = 'screenshot' },
							{ title = LOC "$$$/GPhoto/ExportDialog/Type/Other=Other", value = 'other' },
						},
					},
				},
			},
		},
	}

end

--------------------------------------------------------------------------------
function exportServiceProvider.updateExportSettings( propertyTable )
	logger:trace('updateExportSettings')
	local access_token = GPhotoAPI.refreshToken(propertyTable)
	if access_token then
		propertyTable.access_token = access_token
	end
	require 'GPhotoUser'
	GPhotoUser.verifyLogin( propertyTable )

	local prefs = import 'LrPrefs'.prefsForPlugin()
	if not prefs.counter then
		prefs.counter = 1
	else
		prefs.counter = prefs.counter + 1
	end
	logger:info("counter:", prefs.counter)
end

--------------------------------------------------------------------------------
function exportServiceProvider.processRenderedPhotos( functionContext, exportContext )
	logger:trace('processRenderedPhotos')

	local exportSession = exportContext.exportSession
	local exportSettings = assert( exportContext.propertyTable )
	local nPhotos = exportSession:countRenditions()
	-- GPhotoAPI.refreshToken(exportSettings)

	-- Set progress title.
	local progressScope = exportContext:configureProgress {
						title = nPhotos > 1
									and LOC( "$$$/GPhoto/Publish/Progress=Publishing ^1 photos to GPhoto", nPhotos )
									or LOC "$$$/GPhoto/Publish/Progress/One=Publishing one photo to GPhoto",
					}

	-- Save off uploaded photo IDs so we can take user to those photos later.
	local uploadedPhotoIds = {}

	local publishedCollectionInfo = exportContext.publishedCollectionInfo
	local albumId = publishedCollectionInfo.remoteId
	local isDefaultCollection = publishedCollectionInfo.isDefaultCollection
	if not albumId and not isDefaultCollection then
		albumId = GPhotoAPI.findOrCreateAlbum(exportSettings, publishedCollectionInfo.name)
	end

	-- Get a list of photos already in this photoset so we know which ones we can replace and which have
	-- to be re-uploaded entirely.
	local albumRemoteIds = GPhotoAPI.listPhotosFromAlbum( exportSettings, { albumId = albumId } )

	local albumRemoteIdSet = {}

	-- Turn it into a set for quicker access later.
	if albumRemoteIds then
		for _, photo in ipairs( albumRemoteIds ) do
			logger:trace(string.format('RemoteId %s is exist', photo.remoteId))
			albumRemoteIdSet[ photo.remoteId ] = true
		end
	end

	local couldNotPublishBecauseFreeAccount = {}
	local GPhotoPhotoIdsForRenditions = {}

	local cannotRepublishCount = 0

	-- Gather GPhoto photo IDs, and if we're on a free account, remember the renditions that
	-- had been previously published.
	for i, rendition in exportContext.exportSession:renditions() do
		local GPhotoPhotoId = rendition.publishedPhotoId
		if GPhotoPhotoId then
			-- Check to see if the photo is still on GPhoto.
			if not albumRemoteIdSet[ GPhotoPhotoId ] then --and not isDefaultCollection then
				logger:trace(string.format('RemoteId %s is not found', GPhotoPhotoId))
				GPhotoPhotoId = nil
			end
		end
		GPhotoPhotoIdsForRenditions[ rendition ] = GPhotoPhotoId
	end

	local photosetUrl
	for i, rendition in exportContext:renditions { stopIfCanceled = true } do
		-- Update progress scope.
		progressScope:setPortionComplete( ( i - 1 ) / nPhotos )

		-- Get next photo.
		local photo = rendition.photo

		-- See if we previously uploaded this photo.
		local GPhotoPhotoId = GPhotoPhotoIdsForRenditions[ rendition ]

		if not rendition.wasSkipped then
			local success, pathOrMessage = rendition:waitForRender()

			-- Update progress scope again once we've got rendered photo.
			progressScope:setPortionComplete( ( i - 0.5 ) / nPhotos )

			-- Check for cancellation again after photo has been rendered.
			if progressScope:isCanceled() then break end

			if success then
				-- Build up common metadata for this photo.
				local title = getGPhotoTitle( photo, exportSettings, pathOrMessage )

				local description = photo:getFormattedMetadata( 'caption' )
				local keywordTags = photo:getFormattedMetadata( 'keywordTagsForExport' )

				local tags

				if keywordTags then
					tags = {}
					local keywordIter = string.gfind( keywordTags, "[^,]+" )

					for keyword in keywordIter do
						if string.sub( keyword, 1, 1 ) == ' ' then
							keyword = string.sub( keyword, 2, -1 )
						end
						if string.find( keyword, ' ' ) ~= nil then
							keyword = '"' .. keyword .. '"'
						end
						tags[ #tags + 1 ] = keyword
					end
				end

				-- Upload or replace the photo.
				GPhotoPhotoId = GPhotoAPI.uploadPhoto( exportSettings, {
										photoId = GPhotoPhotoId,
										albumId = albumId,
										filePath = pathOrMessage,
										title = title or '',
										description = description,
										tags = table.concat( tags, ',' ),
									} )
				-- delete temp file.
				LrFileUtils.delete( pathOrMessage )

				-- Remember this in the list of photos we uploaded.
				uploadedPhotoIds[ #uploadedPhotoIds + 1 ] = GPhotoPhotoId

				-- Record this GPhoto ID with the photo so we know to replace instead of upload.
				logger:info('recordPublishedPhotoId:"'..tostring(GPhotoPhotoId)..'"')
				rendition:recordPublishedPhotoId( tostring(GPhotoPhotoId) )
			end
		else
			-- To get the skipped photo out of the to-republish bin.
			logger:info('recordPublishedPhotoId2')
			rendition:recordPublishedPhotoId(rendition.publishedPhotoId)
		end
	end

	if #uploadedPhotoIds > 0 then
		if ( not isDefaultCollection ) then
			logger:info('recordRemoteCollectionId')
			exportSession:recordRemoteCollectionId( albumId )
		end
		-- Set up some additional metadata for this collection.
		--exportSession:recordRemoteCollectionUrl( photosetUrl )
	end

	progressScope:done()
end

--------------------------------------------------------------------------------

return exportServiceProvider
