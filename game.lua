require("game_const")
require("gameobj.key_const")
require("gameobj.gscheduler")
require("event_list")
require("gameobj.gtime")
require("gameobj.gtick")
require("gameobj.logger")
require("gameobj.res_mgr")
require("gameobj.map_info")
require("gameobj.compatible")
require("gameobj.engine_extension") --引擎接口相关扩展
require("module.data_collection.init")

local LanguageModule = require("module.language.language")
require("gameobj.notification_mgr")
local BGSprite = require("boot.bg_sprite")
require( "module.game_audio.game_audio_manager" )
require("ui.ui_utils")
reset_api = require( "gameobj.reset_api" )
util = require("gameobj.util")

game = {}
game.extra_cfg = {}
local cfg_url = "http://protal.q2.175game.com/clientinfo/"
local request = network.createHTTPRequest( function(event)
    local ok = ( event.name == "completed" )
    local request = event.request
    if not ok then
        return
    end

    local code = request:getResponseStatusCode()
    if code ~= 200 then
        return
    end
    game.extra_cfg = json.decode(request:getResponseString()) or {}
end, cfg_url, "GET" )
request:addRequestHeader( "Connection: Keep-Alive" )
request:setTimeout( 30 )
request:start()


-- current scene
game.state          = gameConst.SCENE_OTHER
game.isEditor = false

game.isBeingAttack = false

game.isSceneScaled = gameConst.newLogin
game.isSceneTransitOpened = gameConst.newLogin

game.isLoginScene = true
game.isExit = false

local function doReEnterGame( bool, isLogout )
    game.state = gameConst.SCENE_OTHER
    -- from background to foreground, there doesn't need to confirm
    if isLogout then
        gHasLoaded = false
        require("module.friend.rank").isFirstOpen = true
    end
	game.isSceneScaled = gameConst.newLogin
	game.isSceneTransitOpened = gameConst.newLogin
    game.isLoginScene = true
    gEvent.trigEvent( gEventsList.EV_GAME_REENTERGAME )
    if bool == true then
		require("module.net.connect").disconnect()
        game.isBeingAttack = false
		return game.enterLoginScene()
    end
end

function game.reEnterGame( bool, isLogout )
    if CLIENT_VERSION == 1 then
        doReEnterGame( bool, isLogout )
        return
    end

    if BGSprite.setStep then
        BGSprite.setStep("S001")
    end
    checkIsMaintenanceAndVersion( function()
        doReEnterGame( bool, isLogout )
    end )
end

local EnterBackgroundTimestamp  = 0
local EnterBackgroundTimedelta  = 0
gEnterForegroundTS = 0
function game.getEnterBackgroundTimedelta()
    return EnterBackgroundTimedelta
end

function game.enterForeground()
    gEnterForegroundTS = os.time()

    if EnterBackgroundTimestamp == 0 then
        logger.error( "Enter foreground error!!!!!!!!!!!!" )
        return
    end

    EnterBackgroundTimedelta = os.time() - EnterBackgroundTimestamp
    EnterBackgroundTimestamp = 0

    gNotificationMgr.removeAllNotifications()
    gEvent.trigEvent( gEventsList.EV_ENTER_FOREGROUND, EnterBackgroundTimedelta )

    -- because It will trigger APP_ENTER_FOREGROUND event when playing cg
    -- and login with others sdk
    --[[
    if device.platform == "android" and not game.getIsMainActivity() then
        return game.setIsMainActivity( true )
    end

    if EnterBackgroundTimedelta >= 60 * 1000 then
        return game.reEnterGame( true )
    end
    --]]
end

function game.enterBackground()
    EnterBackgroundTimestamp = os.time()
    gNotificationMgr.addNotification( "SO2", T("主公，快回来吧，您的城池可不能群龙无首啊！"), 172800, 0 ) --48h
    gNotificationMgr.pushAllNotifications()
    gEvent.trigEvent( gEventsList.EV_ENTER_BACKGROUND )
end

local function doStartup()
    local notificationCenter = CCNotificationCenter:sharedNotificationCenter()
    notificationCenter:registerScriptObserver( nil,
                                               game.enterForeground,
                                               "APP_ENTER_FOREGROUND" )
    notificationCenter:registerScriptObserver( nil,
                                               game.enterBackground,
                                               "APP_ENTER_BACKGROUND" )
    gTick.setTimeOut( 1800, function()
        gTick.stop()
		require("module.net.connect").disconnect()

        local title 		= T("主公仍在吗？")
        local context		= T("主公外出太久，暂时失去了与领地的联系。")
        local confirmText	= T("返回领地")
        local confirmCB	= function()
            gTick.start()
            game.reEnterGame( true )
        end
        local alert = require("ui.component.common_confirm")
        alert.showNormal(title, context, confirmCB, confirmText, nil, nil, true)
    end )

    gNotificationMgr.removeAllNotifications()

    -- init music and effects
 	gameAudioManager.initSetting()

    -- start gTick
    gTick.start()

    game.enterLoginScene()
end

function game.startup()
    if CLIENT_VERSION == 1 then
        doStartup()
        return
    end
    if BGSprite.setStep then
        BGSprite.setStep("S001")
    end
    gCollection:startGame()
    checkIsMaintenanceAndVersion( doStartup )
end

function game.exit()
    gNotificationMgr.addNotification( "SO2", T("主公，快回来吧，您的城池可不能群龙无首啊！"), 172800, 0 ) --48h
    gNotificationMgr.pushAllNotifications()
    CCDirector:sharedDirector():endToLua()
    game.isExit = true
end

function game.enterLoginScene()
    display.replaceScene(require("scenes.login_scene").new())
end

game.m_currentScene = nil
function game.getCurrentScene()
    return game.m_currentScene
end

function game.getCurrentSceneType()
    return game.m_currentScene.m_scene
end

function game.setCurrentScene( scene )
    game.m_currentScene = scene
end

function game.getUILayer()
    return game.m_currentScene:getUILayer()
end

local SearchPath = {
    "res/",
    "sound/",
    "res/ui/",
	"res/ui/head/",
	"res/ui/ui_single/",
    "res/ui/treasure/",
	"res/ziku/",
}

PRELOAD_RES = {
    {"plist",   kCCTexture2DPixelFormat_RGBA4444, "ui/transit_pic.plist"},
    {"plist",   kCCTexture2DPixelFormat_RGBA4444, "ui/shop1.plist"},
}

local NeedRetainPlist8888 = {
}

local NeedRetainPlist4444 = {
    "ui/ui1.plist",
    "building/batch_building.plist"
}

local NeedRetainTextures4444 = {
    "num_0.png",
    "ziku_26_0.png",
    "ziku_biaoti_0.png",
    "ziku_zjm_0.png"
}

function game.__init__()
    -- quick-cocos2dx has helped us set randomseed, see framework.__init__
    -- initRandom()
    CCTexture2D:setDefaultAlphaPixelFormat(DEFAULT_FORMAT)

    if gFrameRate then
        CCDirector:sharedDirector():setAnimationInterval(1/gFrameRate)
    end

    CCDirector:sharedDirector():setProjection( 0 )

    local FileUtils = CCFileUtils:sharedFileUtils()
    local p         = FileUtils:getWritablePath() .. "q2.game.qtz.com/"
    FileUtils:addSearchPath( p )

    for k, searchPath in ipairs( SearchPath ) do
        FileUtils:addSearchPath( p .. searchPath )
    end

    for k, searchPath in ipairs( SearchPath ) do
        FileUtils:addSearchPath( searchPath )
    end

    local loadingMgr = require( "module.loading.loading_manager" )
	if device.platform == "ios" and not IS_HD_VERSION then
        loadingMgr.addResToLoadingOnceList("res/bgs/map.plist", "plist", kCCTexture2DPixelFormat_PVRTC4)
    elseif device.platform == "android" and not IS_HD_VERSION then
		CCSpriteFrameCache:sharedSpriteFrameCache():addSpriteFramesWithFile("res/bgs/map.plist", "res/bgs/map.pkm")
	elseif device.platform == "android" and IS_HD_VERSION then
		CCSpriteFrameCache:sharedSpriteFrameCache():addSpriteFramesWithFile("res/bgs/q_background_03.plist", "res/bgs/q_background_03.pkm")
		CCSpriteFrameCache:sharedSpriteFrameCache():addSpriteFramesWithFile("res/bgs/q_background_04.plist", "res/bgs/q_background_04.pkm")
	elseif device.platform == "ios" and IS_HD_VERSION then
		CCSpriteFrameCache:sharedSpriteFrameCache():addSpriteFramesWithFile("res/bgs/q_background_03.plist", "res/bgs/q_background_03.pvr.ccz")
		CCSpriteFrameCache:sharedSpriteFrameCache():addSpriteFramesWithFile("res/bgs/q_background_04.plist", "res/bgs/q_background_04.pvr.ccz")
	else
        loadingMgr.addResToLoadingOnceList("bgs/q_background_01.jpg", "png", kCCTexture2DPixelFormat_RGBA8888)
        loadingMgr.addResToLoadingOnceList("bgs/q_background_02.jpg", "png", kCCTexture2DPixelFormat_RGBA8888)
        loadingMgr.addResToLoadingOnceList("bgs/q_background_03.jpg", "png", kCCTexture2DPixelFormat_RGBA8888)
        loadingMgr.addResToLoadingOnceList("bgs/q_background_04.jpg", "png", kCCTexture2DPixelFormat_RGBA8888)
    end

    for k, v in pairs( PRELOAD_RES ) do
        loadingMgr.addResToLoadingOnceList( v[3], v[1], v[2] )
    end

    for k, v in ipairs( NeedRetainPlist8888 ) do
        ResMgr.loadPlist( v, kCCTexture2DPixelFormat_RGBA8888 )
    end

    for k, v in ipairs( NeedRetainPlist4444 ) do
        if IS_HD_VERSION then
            ResMgr.loadPlist( v, kCCTexture2DPixelFormat_RGBA8888 )
        else
            ResMgr.loadPlist( v, kCCTexture2DPixelFormat_RGBA4444 )
        end
    end

    for k, v in ipairs( NeedRetainTextures4444 ) do
        if IS_HD_VERSION then
            ResMgr.retainTexture( v, kCCTexture2DPixelFormat_RGBA8888 )
        else
            ResMgr.retainTexture( v, kCCTexture2DPixelFormat_RGBA4444 )
        end
    end
end

local function recheck_client()
    local UpdateURLMgr = require( "boot.update_url_mgr" )
    local filepath = updatemgr.res_path .. "/updateInfo.zip" 
    if not io.exists(filepath) then
        return
    end
    CCLuaLoadChunksFromZip(filepath)
    package.loaded[ "updateInfo.lua" ] = nil
    _G[ "updateInfo.lua" ] = nil
    local updateInfo= require( "updateInfo.lua" )
    local reupdate_files = {}
    for k,v in pairs(updateInfo) do
        local filename = updatemgr.res_path .. "/" .. k 
        if io.exists(filename) then
            local real_md5 = md5file(filename)
            if real_md5 and real_md5 ~= v then
                table.insert(reupdate_files, {k,v})
            end
        end
    end

    local function download(url, filename, callback )
        local request = network.createHTTPRequest( function( event )
            local ok = ( event.name == "completed" )
            local request =  event.request
            if not ok then
                return http.callback( request:getErrorCode(), request:getErrorCode() )  
            end

            local code = request:getResponseStatusCode()
            local response = ""
            if code == 200 then
                if not filename then
                    response = request:getResponseString()
                else
                    request:saveResponseData( filename )
                end
                callback(response)
                return
            end


            local title = sys_strings.get( "T_01" )
            local btns  = {
                sys_strings.get( "OK" )
            }
            local msg   = string.format( sys_strings.get( "NE_02" ), code, http.getfilename(url) )
            device.showAlert( title, msg, btns, function( event )
                CCDirector:sharedDirector():endToLua()
            end)
        end, url, "GET" )
        request:addRequestHeader( "Connection: Keep-Alive" )
        request:setTimeout( 30 )
        request:start()
    end

    local function file_update(files)
        local file_info = table.remove(files, 1)
        if file_info == nil then
            return
        end
        local filename = file_info[1]
        local md5 = file_info[2]
        local url = string.format( "%s?version=%s",  UpdateURLMgr.getRealURL( filename ), md5 )
        local real_patch = updatemgr.res_path .. "/" .. filename 
        download(url, real_patch, function(msg)
            local real_md5 = md5file(real_patch)
            if real_patch and real_md5 ~= md5 then
                local pTitle = sys_strings.get("T_01")
                local pBtn   = sys_strings.get("OK")
                device.showAlert( pTitle, pTitle, { pBtn }, function( event )
                    CCDirector:sharedDirector():endToLua()
                end )
                return
            end
            file_update(files)  
        end)
    end
    file_update(reupdate_files)
end

--[[
if util.getRegion() == util.REGION_CN then
    recheck_client()
end
--]]


if CLIENT_VERSION == 2 then
    local scheduler = require(__FRAMEWORK_PACKAGE_NAME__ .. ".scheduler")

    scheduler.scheduleGlobal(function()
        CCTextureCache:sharedTextureCache():removeUnusedTextures()
    end, 5)
end

game.__init__()
