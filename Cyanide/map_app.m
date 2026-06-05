//
//  map_app.m
//  Cyanide
//  Adapted from https://github.com/d1y/cyanide-ios (AGPL-3.0).
//

#import "map_app.h"

static NSString *CNDIconBaseName(NSString *name)
{
    NSString *ext = name.pathExtension.lowercaseString;
    NSString *base = ([ext isEqualToString:@"png"] ||
                      [ext isEqualToString:@"jpg"] ||
                      [ext isEqualToString:@"jpeg"] ||
                      [ext isEqualToString:@"heic"] ||
                      [ext isEqualToString:@"webp"])
        ? name.stringByDeletingPathExtension
        : name;
    BOOL changed = YES;
    while (changed && base.length > 0) {
        changed = NO;
        for (NSString *suffix in @[
                 @"@3x",
                 @"@2x",
                 @"~iphone",
                 @"~ipad",
                 @"-large",
                 @"-small",
                 @"-dark",
                 @"-light",
                 @".past",
                 @"past",
                 @".icon.720p",
                 @"icon.720p",
                 @"ic.launcher",
                 @"ic_launcher",
                 @"icon",
             ]) {
            if ([base hasSuffix:suffix]) {
                base = [base substringToIndex:base.length - suffix.length];
                changed = YES;
            }
        }
    }
    return base;
}

static NSString *CNDCompactAliasKey(NSString *name)
{
    NSString *lower = name.lowercaseString;
    NSMutableString *out = [NSMutableString stringWithCapacity:lower.length];
    NSCharacterSet *skip = [NSCharacterSet characterSetWithCharactersInString:@" _-."];
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ([skip characterIsMember:c]) continue;
        [out appendFormat:@"%C", c];
    }
    return out;
}

static NSDictionary<NSString *, NSString *> *CNDAppIconAliases(void)
{
    static NSDictionary<NSString *, NSString *> *aliases = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        aliases = @{
            @"appstore": @"com.apple.AppStore",
            @"com.apple.appstore": @"com.apple.AppStore",
            @"settings": @"com.apple.Preferences",
            @"preferences": @"com.apple.Preferences",
            @"com.apple.preferences": @"com.apple.Preferences",
            @"messages": @"com.apple.MobileSMS",
            @"sms": @"com.apple.MobileSMS",
            @"com.apple.mobilesms": @"com.apple.MobileSMS",
            @"phone": @"com.apple.mobilephone",
            @"safari": @"com.apple.mobilesafari",
            @"mail": @"com.apple.mobilemail",
            @"calendar": @"com.apple.mobilecal",
            @"clock": @"com.apple.mobiletimer",
            @"maps": @"com.apple.Maps",
            @"com.apple.maps": @"com.apple.Maps",
            @"photos": @"com.apple.mobileslideshow",
            @"camera": @"com.apple.camera",
            @"notes": @"com.apple.mobilenotes",
            @"reminders": @"com.apple.reminders",
            @"weather": @"com.apple.weather",
            @"music": @"com.apple.Music",
            @"com.apple.music": @"com.apple.Music",
            @"contacts": @"com.apple.MobileAddressBook",
            @"com.apple.mobileaddressbook": @"com.apple.MobileAddressBook",
            @"com.apple.contacts": @"com.apple.MobileAddressBook",
            @"facetime": @"com.apple.facetime",
            @"findmy": @"com.apple.findmy",
            @"findiphone": @"com.apple.findmy",
            @"findmyiphone": @"com.apple.findmy",
            @"com.apple.mobileme.fmip1": @"com.apple.findmy",
            @"calculator": @"com.apple.calculator",
            @"compass": @"com.apple.compass",
            @"wallet": @"com.apple.Passbook",
            @"passbook": @"com.apple.Passbook",
            @"com.apple.passbook": @"com.apple.Passbook",
            @"books": @"com.apple.iBooks",
            @"ibooks": @"com.apple.iBooks",
            @"com.apple.ibooks": @"com.apple.iBooks",
            @"itunesstore": @"com.apple.iTunesStore",
            @"com.apple.itunesstore": @"com.apple.iTunesStore",
            @"voicememos": @"com.apple.VoiceMemos",
            @"com.apple.voicememos": @"com.apple.VoiceMemos",
            @"health": @"com.apple.Health",
            @"home": @"com.apple.Home",
            @"shortcuts": @"com.apple.shortcuts",
            @"translate": @"com.apple.Translate",
            @"freeform": @"com.apple.freeform",
            @"journal": @"com.apple.Journal",

            @"alipay": @"com.alipay.iphoneclient",
            @"支付宝": @"com.alipay.iphoneclient",
            @"com.eg.android.alipaygphone": @"com.alipay.iphoneclient",
            @"taobao": @"com.taobao.taobao4iphone",
            @"淘宝": @"com.taobao.taobao4iphone",
            @"淘宝iphone": @"com.taobao.taobao4iphone",
            @"com.taobao.taobao": @"com.taobao.taobao4iphone",
            @"amap": @"com.autonavi.minimap",
            @"gaode": @"com.autonavi.minimap",
            @"gaodemap": @"com.autonavi.minimap",
            @"autonavi": @"com.autonavi.minimap",
            @"高德": @"com.autonavi.minimap",
            @"高德地图": @"com.autonavi.minimap",
            @"com.autonavi.minimap": @"com.autonavi.minimap",
            @"pinduoduo": @"com.xunmeng.pinduoduo",
            @"pdd": @"com.xunmeng.pinduoduo",
            @"拼多多": @"com.xunmeng.pinduoduo",
            @"shadowrocket": @"com.liguangming.Shadowrocket",
            @"com.liguangming.shadowrocket": @"com.liguangming.Shadowrocket",
            @"twitter": @"com.atebits.Tweetie2",
            @"tweetie": @"com.atebits.Tweetie2",
            @"tweetie2": @"com.atebits.Tweetie2",
            @"com.atebits.tweetie2": @"com.atebits.Tweetie2",
            @"biliblue": @"tv.danmaku.biliblue",
            @"bilibili": @"tv.danmaku.bilianime",
            @"bilibili蓝版": @"tv.danmaku.biliblue",
            @"com.bilibili.app.blue": @"tv.danmaku.biliblue",
            @"tv.danmaku.bili": @"tv.danmaku.bilianime",

            @"wechat": @"com.tencent.xin",
            @"weixin": @"com.tencent.xin",
            @"微信": @"com.tencent.xin",
            @"com.tencent.mm": @"com.tencent.xin",
            @"qq": @"com.tencent.mqq",
            @"com.tencent.mobileqq": @"com.tencent.mqq",
            @"qqmusic": @"com.tencent.QQMusic",
            @"com.tencent.qqmusic": @"com.tencent.QQMusic",
            @"jingdong": @"com.360buy.jdmobile",
            @"jd": @"com.360buy.jdmobile",
            @"京东": @"com.360buy.jdmobile",
            @"com.jingdong.app.mall": @"com.360buy.jdmobile",
            @"douyin": @"com.ss.iphone.ugc.Aweme",
            @"抖音": @"com.ss.iphone.ugc.Aweme",
            @"com.ss.android.ugc.aweme": @"com.ss.iphone.ugc.Aweme",
            @"kuaishou": @"com.kuaishou.gifmaker",
            @"快手": @"com.kuaishou.gifmaker",
            @"com.smile.gifmaker": @"com.kuaishou.gifmaker",
            @"meituan": @"com.meituan.imeituan",
            @"美团": @"com.meituan.imeituan",
            @"com.sankuai.meituan": @"com.meituan.imeituan",
            @"eleme": @"me.ele.ios.eleme",
            @"饿了么": @"me.ele.ios.eleme",
            @"me.ele": @"me.ele.ios.eleme",
            @"xiaohongshu": @"com.xingin.discover",
            @"xhs": @"com.xingin.discover",
            @"小红书": @"com.xingin.discover",
            @"com.xingin.xhs": @"com.xingin.discover",
            @"baidumap": @"com.baidu.map",
            @"百度地图": @"com.baidu.map",
            @"com.baidu.baidumap": @"com.baidu.map",
            @"baidu": @"com.baidu.searchbox",
            @"百度": @"com.baidu.searchbox",
            @"com.baidu.searchbox": @"com.baidu.searchbox",
            @"didichuxing": @"com.xiaojukeji.didi",
            @"didi": @"com.xiaojukeji.didi",
            @"滴滴": @"com.xiaojukeji.didi",
            @"com.sdu.didi.psnger": @"com.xiaojukeji.didi",
            @"neteasemusic": @"com.netease.cloudmusic",
            @"网易云音乐": @"com.netease.cloudmusic",
            @"com.netease.cloudmusic": @"com.netease.cloudmusic",
            @"zhihu": @"com.zhihu.ios",
            @"知乎": @"com.zhihu.ios",
            @"com.zhihu.android": @"com.zhihu.ios",
            @"zhihudaily": @"com.zhihu.daily",
            @"知乎日报": @"com.zhihu.daily",
            @"com.zhihu.daily.android": @"com.zhihu.daily",
            @"boss": @"com.hpbr.bosszhipin",
            @"bosszhipin": @"com.hpbr.bosszhipin",
            @"boss直聘": @"com.hpbr.bosszhipin",
            @"直聘": @"com.hpbr.bosszhipin",
            @"com.hpbr.bosszhipin": @"com.hpbr.bosszhipin",
            @"zhaopin": @"com.zhaopin.social",
            @"智联招聘": @"com.zhaopin.social",
            @"com.zhaopin.social": @"com.zhaopin.social",
            @"maimai": @"com.taou.maimai",
            @"脉脉": @"com.taou.maimai",
            @"com.taou.maimai": @"com.taou.maimai",
            @"jdjr": @"com.jd.jrapp",
            @"jdfinance": @"com.jd.jrapp",
            @"京东金融": @"com.jd.jrapp",
            @"com.jd.jrapp": @"com.jd.jrapp",
            @"jingdongdaojia": @"com.jd.pdj",
            @"jddaojia": @"com.jd.pdj",
            @"京东到家": @"com.jd.pdj",
            @"com.jingdong.pdj": @"com.jd.pdj",
            @"cainiao": @"com.cainiao.Cainiao4iPhone",
            @"菜鸟": @"com.cainiao.Cainiao4iPhone",
            @"菜鸟裹裹": @"com.cainiao.Cainiao4iPhone",
            @"com.cainiao.wireless": @"com.cainiao.Cainiao4iPhone",
            @"qianniu": @"com.taobao.QN",
            @"千牛": @"com.taobao.QN",
            @"com.taobao.qianniu": @"com.taobao.QN",
            @"etao": @"com.taobao.etao",
            @"一淘": @"com.taobao.etao",
            @"com.taobao.etao": @"com.taobao.etao",
            @"youku": @"com.youku.YouKu",
            @"优酷": @"com.youku.YouKu",
            @"com.youku.phone": @"com.youku.YouKu",
            @"iqiyi": @"com.qiyi.iphone",
            @"爱奇艺": @"com.qiyi.iphone",
            @"com.qiyi.video": @"com.qiyi.iphone",
            @"mgtv": @"com.hunantv.imgo.activity",
            @"芒果tv": @"com.hunantv.imgo.activity",
            @"com.hunantv.imgo.activity": @"com.hunantv.imgo.activity",
            @"xunlei": @"com.xunlei.download",
            @"迅雷": @"com.xunlei.download",
            @"com.xunlei.downloadprovider": @"com.xunlei.download",
            @"ctrip": @"ctrip.com",
            @"xiecheng": @"ctrip.com",
            @"携程": @"ctrip.com",
            @"ctrip.android.view": @"ctrip.com",
            @"com.android.ctrip.gs": @"ctrip.com",
            @"com.android.ctrip.gsic.launcher": @"ctrip.com",
            @"qunar": @"com.qunar.iphoneclient",
            @"去哪儿": @"com.qunar.iphoneclient",
            @"com.qunar": @"com.qunar.iphoneclient",
            @"tongcheng": @"com.ly.iphone",
            @"同程旅行": @"com.ly.iphone",
            @"com.tongcheng.android": @"com.ly.iphone",
            @"baidunetdisk": @"com.baidu.netdisk",
            @"百度网盘": @"com.baidu.netdisk",
            @"com.baidu.netdisk": @"com.baidu.netdisk",
            @"tieba": @"com.baidu.tieba",
            @"baidutieba": @"com.baidu.tieba",
            @"百度贴吧": @"com.baidu.tieba",
            @"com.baidu.tieba": @"com.baidu.tieba",
            @"baiduwenku": @"com.baidu.Wenku",
            @"百度文库": @"com.baidu.Wenku",
            @"com.baidu.wenku": @"com.baidu.Wenku",
            @"baidutranslate": @"com.baidu.Translate",
            @"百度翻译": @"com.baidu.Translate",
            @"com.baidu.baidutranslate": @"com.baidu.Translate",
            @"qqmail": @"com.tencent.qqmail",
            @"qq邮箱": @"com.tencent.qqmail",
            @"com.tencent.androidqqmail": @"com.tencent.qqmail",
            @"quanminkge": @"com.tencent.karaoke",
            @"quanminge": @"com.tencent.karaoke",
            @"全民k歌": @"com.tencent.karaoke",
            @"com.tencent.karaoke": @"com.tencent.karaoke",
            @"qqlite": @"com.tencent.qqlite",
            @"qq轻聊版": @"com.tencent.qqlite",
            @"com.tencent.qqlite": @"com.tencent.qqlite",
            @"yingyongbao": @"com.tencent.androidqqdownloader",
            @"应用宝": @"com.tencent.androidqqdownloader",
            @"com.tencent.android.qqdownloader": @"com.tencent.androidqqdownloader",
            @"tencentnews": @"com.tencent.news",
            @"腾讯新闻": @"com.tencent.news",
            @"com.tencent.news": @"com.tencent.news",
            @"weishi": @"com.tencent.weishi",
            @"微视": @"com.tencent.weishi",
            @"com.tencent.weishi": @"com.tencent.weishi",
            @"douban": @"com.douban.frodo",
            @"豆瓣": @"com.douban.frodo",
            @"com.douban.frodo": @"com.douban.frodo",
            @"lofter": @"com.netease.lofter",
            @"com.netease.loftercam.activity": @"com.netease.lofter",
            @"wangyiyanxuan": @"com.netease.yanxuan",
            @"网易严选": @"com.netease.yanxuan",
            @"com.netease.yanxuan": @"com.netease.yanxuan",
            @"neteasenews": @"com.netease.news",
            @"网易新闻": @"com.netease.news",
            @"com.netease.newsreader.activity": @"com.netease.news",
            @"youdaodict": @"com.youdao.dict",
            @"网易有道词典": @"com.youdao.dict",
            @"com.youdao.dict": @"com.youdao.dict",
            @"ximalaya": @"com.gemd.iting",
            @"喜马拉雅": @"com.gemd.iting",
            @"com.ximalaya.ting.android": @"com.gemd.iting",
            @"douyu": @"air.tv.douyu.douyutv",
            @"斗鱼": @"air.tv.douyu.douyutv",
            @"air.tv.douyu.android": @"air.tv.douyu.douyutv",
            @"huya": @"com.duowan.HUYA",
            @"虎牙": @"com.duowan.HUYA",
            @"com.duowan.kiwi": @"com.duowan.HUYA",
            @"xiaomi": @"com.xiaomi.mishop",
            @"小米商城": @"com.xiaomi.mishop",
            @"com.xiaomi.shop": @"com.xiaomi.mishop",
            @"mijia": @"com.xiaomi.mihome",
            @"米家": @"com.xiaomi.mihome",
            @"com.xiaomi.smarthome": @"com.xiaomi.mihome",
            @"cmb": @"cmb.pb",
            @"招商银行": @"cmb.pb",
            @"cmbchina": @"cmb.pb",
            @"掌上生活": @"com.cmbchina.ccd.pluto.cmbactivity",
            @"com.cmbchina.ccd.pluto.cmbactivity": @"com.cmbchina.ccd.pluto.cmbactivity",
            @"icbc": @"com.icbc.iphoneclient",
            @"工商银行": @"com.icbc.iphoneclient",
            @"com.icbc": @"com.icbc.iphoneclient",
            @"ccb": @"com.ccb.ccbMobileBank",
            @"建设银行": @"com.ccb.ccbMobileBank",
            @"com.chinamworld.main": @"com.ccb.ccbMobileBank",
            @"abc": @"com.abchina.iphone.abchina",
            @"农业银行": @"com.abchina.iphone.abchina",
            @"com.android.bankabc": @"com.abchina.iphone.abchina",
            @"boc": @"com.bocmbci.bocmbci",
            @"中国银行": @"com.bocmbci.bocmbci",
            @"com.chinamworld.bocmbci": @"com.bocmbci.bocmbci",
            @"spdb": @"cn.com.spdb.mobilebank.per",
            @"浦发银行": @"cn.com.spdb.mobilebank.per",
            @"cn.com.spdb.mobilebank.per": @"cn.com.spdb.mobilebank.per",
            @"citic": @"com.ecitic.bank.mobile",
            @"中信银行": @"com.ecitic.bank.mobile",
            @"pinganbank": @"com.pingan.pabank",
            @"平安银行": @"com.pingan.pabank",
            @"com.pingan.pabank.activity": @"com.pingan.pabank",
            @"pingan": @"com.pingan.paces.ccms",
            @"平安金管家": @"com.pingan.paces.ccms",
            @"com.pingan.papd": @"com.pingan.paces.ccms",

            @"google": @"com.google.GoogleMobile",
            @"com.google.android.googlequicksearchbox": @"com.google.GoogleMobile",
            @"gmail": @"com.google.Gmail",
            @"com.google.android.gm": @"com.google.Gmail",
            @"googlemaps": @"com.google.Maps",
            @"com.google.android.apps.maps": @"com.google.Maps",
            @"youtube": @"com.google.ios.youtube",
            @"com.google.android.youtube": @"com.google.ios.youtube",
            @"chrome": @"com.google.chrome.ios",
            @"com.android.chrome": @"com.google.chrome.ios",
            @"com.google.android.apps.chrome": @"com.google.chrome.ios",
            @"googlephotos": @"com.google.photos",
            @"com.google.android.apps.photos": @"com.google.photos",
            @"googledrive": @"com.google.Drive",
            @"com.google.android.apps.docs": @"com.google.Drive",
            @"googledocs": @"com.google.Docs",
            @"com.google.android.apps.docs.editors.docs": @"com.google.Docs",
            @"googlesheets": @"com.google.Sheets",
            @"com.google.android.apps.docs.editors.sheets": @"com.google.Sheets",
            @"googleslides": @"com.google.Slides",
            @"com.google.android.apps.docs.editors.slides": @"com.google.Slides",
            @"googletranslate": @"com.google.Translate",
            @"com.google.android.apps.translate": @"com.google.Translate",
            @"googlecalendar": @"com.google.Calendar",
            @"com.google.android.calendar": @"com.google.Calendar",
            @"googlekeep": @"com.google.Keep",
            @"com.google.android.keep": @"com.google.Keep",
            @"googlemeet": @"com.google.meetings",
            @"com.google.android.apps.meetings": @"com.google.meetings",

            @"facebook": @"com.facebook.Facebook",
            @"com.facebook.katana": @"com.facebook.Facebook",
            @"messenger": @"com.facebook.Messenger",
            @"com.facebook.orca": @"com.facebook.Messenger",
            @"instagram": @"com.burbn.instagram",
            @"com.instagram.android": @"com.burbn.instagram",
            @"whatsapp": @"net.whatsapp.WhatsApp",
            @"com.whatsapp": @"net.whatsapp.WhatsApp",
            @"telegram": @"ph.telegra.Telegraph",
            @"org.telegram.messenger": @"ph.telegra.Telegraph",
            @"signal": @"org.whispersystems.signal",
            @"org.thoughtcrime.securesms": @"org.whispersystems.signal",
            @"discord": @"com.hammerandchisel.discord",
            @"com.discord": @"com.hammerandchisel.discord",
            @"reddit": @"com.reddit.Reddit",
            @"com.reddit.frontpage": @"com.reddit.Reddit",
            @"snapchat": @"com.toyopagroup.picaboo",
            @"com.snapchat.android": @"com.toyopagroup.picaboo",
            @"tiktok": @"com.zhiliaoapp.musically",
            @"com.zhiliaoapp.musically": @"com.zhiliaoapp.musically",
            @"com.twitter.android": @"com.atebits.Tweetie2",
            @"linkedin": @"com.linkedin.LinkedIn",
            @"com.linkedin.android": @"com.linkedin.LinkedIn",
            @"pinterest": @"pinterest",
            @"com.pinterest": @"pinterest",
            @"tumblr": @"com.tumblr.tumblr",
            @"com.tumblr": @"com.tumblr.tumblr",

            @"spotify": @"com.spotify.client",
            @"com.spotify.music": @"com.spotify.client",
            @"netflix": @"com.netflix.Netflix",
            @"com.netflix.mediaclient": @"com.netflix.Netflix",
            @"primevideo": @"com.amazon.aiv.AIVApp",
            @"com.amazon.avod.thirdpartyclient": @"com.amazon.aiv.AIVApp",
            @"amazon": @"com.amazon.Amazon",
            @"com.amazon.mshop.android.shopping": @"com.amazon.Amazon",
            @"twitch": @"tv.twitch",
            @"tv.twitch.android.app": @"tv.twitch",
            @"disneyplus": @"com.disney.disneyplus",
            @"com.disney.disneyplus": @"com.disney.disneyplus",
            @"hulu": @"com.hulu.plus",
            @"com.hulu.plus": @"com.hulu.plus",
            @"soundcloud": @"com.soundcloud.TouchApp",
            @"com.soundcloud.android": @"com.soundcloud.TouchApp",
            @"deezer": @"com.deezer.Deezer",
            @"deezer.android.app": @"com.deezer.Deezer",

            @"outlook": @"com.microsoft.Office.Outlook",
            @"com.microsoft.office.outlook": @"com.microsoft.Office.Outlook",
            @"teams": @"com.microsoft.skype.teams",
            @"com.microsoft.teams": @"com.microsoft.skype.teams",
            @"onedrive": @"com.microsoft.skydrive",
            @"com.microsoft.skydrive": @"com.microsoft.skydrive",
            @"word": @"com.microsoft.Office.Word",
            @"com.microsoft.office.word": @"com.microsoft.Office.Word",
            @"excel": @"com.microsoft.Office.Excel",
            @"com.microsoft.office.excel": @"com.microsoft.Office.Excel",
            @"powerpoint": @"com.microsoft.Office.Powerpoint",
            @"com.microsoft.office.powerpoint": @"com.microsoft.Office.Powerpoint",
            @"zoom": @"us.zoom.videomeetings",
            @"us.zoom.videomeetings": @"us.zoom.videomeetings",
            @"slack": @"com.tinyspeck.chatlyio",
            @"com.slack": @"com.tinyspeck.chatlyio",
            @"notion": @"notion.id",
            @"notion.id": @"notion.id",
            @"todoist": @"com.todoist.ios",
            @"com.todoist": @"com.todoist.ios",
            @"evernote": @"com.evernote.iPhone.Evernote",
            @"com.evernote": @"com.evernote.iPhone.Evernote",
            @"dropbox": @"com.getdropbox.Dropbox",
            @"com.dropbox.android": @"com.getdropbox.Dropbox",
            @"github": @"com.github.stormbreaker.prod",
            @"com.github.android": @"com.github.stormbreaker.prod",
            @"chatgpt": @"com.openai.chat",
            @"com.openai.chatgpt": @"com.openai.chat",
            @"perplexity": @"ai.perplexity.app",
            @"ai.perplexity.app.android": @"ai.perplexity.app",
            @"claude": @"com.anthropic.claude",
            @"com.anthropic.claude": @"com.anthropic.claude",

            @"uber": @"com.ubercab.UberClient",
            @"com.ubercab": @"com.ubercab.UberClient",
            @"airbnb": @"com.airbnb.app",
            @"com.airbnb.android": @"com.airbnb.app",
            @"booking": @"com.booking.BookingApp",
            @"com.booking": @"com.booking.BookingApp",
            @"tripadvisor": @"com.tripadvisor.TripAdvisor",
            @"com.tripadvisor.tripadvisor": @"com.tripadvisor.TripAdvisor",
            @"waze": @"com.waze.iphone",
            @"com.waze": @"com.waze.iphone",
            @"yelp": @"com.yelp.yelpiphone",
            @"com.yelp.android": @"com.yelp.yelpiphone",
            @"doordash": @"com.doordash.Consumer",
            @"com.dd.doordash": @"com.doordash.Consumer",
            @"paypal": @"com.paypal.ppmobile",
            @"com.paypal.android.p2pmobile": @"com.paypal.ppmobile",
            @"venmo": @"net.kortina.labs.Venmo",
            @"com.venmo": @"net.kortina.labs.Venmo",
            @"cashapp": @"com.squareup.cash",
            @"com.squareup.cash": @"com.squareup.cash",
            @"coinbase": @"com.coinbase.Coinbase",
            @"com.coinbase.android": @"com.coinbase.Coinbase",
            @"wise": @"com.transferwise.TransferWise",
            @"com.transferwise.android": @"com.transferwise.TransferWise",

            @"weibo": @"com.sina.weibo",
            @"微博": @"com.sina.weibo",
            @"com.sina.weibo": @"com.sina.weibo",
            @"tmall": @"com.tmall.wireless",
            @"天猫": @"com.tmall.wireless",
            @"com.tmall.wireless": @"com.tmall.wireless",
            @"xianyu": @"com.taobao.fleamarket",
            @"闲鱼": @"com.taobao.fleamarket",
            @"com.taobao.idlefish": @"com.taobao.fleamarket",
            @"1688": @"com.alibaba.wireless",
            @"com.alibaba.wireless": @"com.alibaba.wireless",
            @"dingtalk": @"com.laiwang.DingTalk",
            @"钉钉": @"com.laiwang.DingTalk",
            @"com.alibaba.android.rimet": @"com.laiwang.DingTalk",
            @"wecom": @"com.tencent.ww",
            @"企业微信": @"com.tencent.ww",
            @"com.tencent.wework": @"com.tencent.ww",
            @"feishu": @"com.larksuite.Lark",
            @"飞书": @"com.larksuite.Lark",
            @"com.ss.android.lark": @"com.larksuite.Lark",
            @"meituanwaimai": @"com.meituan.waimai",
            @"美团外卖": @"com.meituan.waimai",
            @"com.sankuai.meituan.takeoutnew": @"com.meituan.waimai",
            @"dianping": @"com.dianping.dpscope",
            @"大众点评": @"com.dianping.dpscope",
            @"com.dianping.v1": @"com.dianping.dpscope",
            @"tencentmap": @"com.tencent.map",
            @"腾讯地图": @"com.tencent.map",
            @"com.tencent.map": @"com.tencent.map",
            @"qqbrowser": @"com.tencent.mttlite",
            @"qq浏览器": @"com.tencent.mttlite",
            @"com.tencent.mtt": @"com.tencent.mttlite",
            @"tencentvideo": @"com.tencent.live4iphone",
            @"腾讯视频": @"com.tencent.live4iphone",
            @"com.tencent.qqlive": @"com.tencent.live4iphone",
            @"toutiao": @"com.ss.iphone.article.News",
            @"今日头条": @"com.ss.iphone.article.News",
            @"com.ss.android.article.news": @"com.ss.iphone.article.News",
            @"wps": @"com.kingsoft.wpsoffice",
            @"cn.wps.moffice_eng": @"com.kingsoft.wpsoffice",
            @"keep": @"com.gotokeep.Keep",
            @"com.gotokeep.keep": @"com.gotokeep.Keep",
            @"dewu": @"com.siwuai.duapp",
            @"得物": @"com.siwuai.duapp",
            @"com.shizhuang.duapp": @"com.siwuai.duapp",
            @"smzdm": @"com.smzdm.client.iphone",
            @"什么值得买": @"com.smzdm.client.iphone",
            @"com.smzdm.client.android": @"com.smzdm.client.iphone",

            // User-local SmartisanOS theme compatibility.
            // These source icons exist in SmartisanOS.theme/IconBundles and are
            // used as closest semantic matches for apps without dedicated art.
            @"com.kapinote.ai": @"com.kapinote.ai",
            @"qnq.nuosike.sign": @"qnq.nuosike.sign",
            @"com.danbo.dbxq2": @"com.danbo.dbxq2",
            @"jxd.devapp.ireadnote": @"jxd.devapp.iReadNote",
            @"ireadnote": @"jxd.devapp.iReadNote",
            @"爱阅记": @"jxd.devapp.iReadNote",
            @"app.nicegram": @"app.nicegram",
            @"app.swiftgram.ios": @"app.swiftgram.ios",
            @"com.swiftgram.swiftgram": @"app.swiftgram.ios",
            @"swiftgram": @"app.swiftgram.ios",
            @"nicegram": @"app.nicegram",

            // Common China carrier package aliases.
            @"cn.10086.app": @"com.chinamobile.cmcc",
            @"com.greenpoint.android.mc10086.activity": @"com.chinamobile.cmcc",
            @"com.chinamobile.cmcc": @"com.chinamobile.cmcc",
            @"com.sinovatech.unicom.ui": @"com.sinovatech.unicom.ui",
            @"com.chinaunicom.mobilebusiness": @"com.sinovatech.unicom.ui",
            @"com.chinaunicom.mobileb": @"com.sinovatech.unicom.ui",
            @"ctclient": @"com.chinatelecom.189client",
            @"com.chinatelecom.189client": @"com.chinatelecom.189client",
            @"com.chinatelecom.bestpayclient": @"com.chinatelecom.189client",
        };
    });
    return aliases;
}

static NSDictionary<NSString *, NSArray<NSString *> *> *CNDAppIconMultiAliases(void)
{
    static NSDictionary<NSString *, NSArray<NSString *> *> *aliases = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        aliases = @{
            @"ph.telegra.telegraph": @[
                @"ph.telegra.Telegraph",
                @"app.nicegram",
                @"app.swiftgram.ios",
            ],
            @"org.telegram.messenger": @[
                @"ph.telegra.Telegraph",
                @"app.nicegram",
                @"app.swiftgram.ios",
            ],
            @"telegram": @[
                @"ph.telegra.Telegraph",
                @"app.nicegram",
                @"app.swiftgram.ios",
            ],
            @"me.bakumon.moneykeeper": @[
                @"me.bakumon.moneykeeper",
                @"com.kapinote.ai",
            ],
            @"com.blackcat.app": @[
                @"com.Blackcat.app",
                @"com.macxk.KMusic",
            ],
            @"com.tencent.kittypong": @[
                @"com.tencent.kittypong",
                @"com.sigkitten.litter",
            ],
            @"com.smartisan.reader": @[
                @"com.smartisan.reader",
                @"jxd.devapp.iReadNote",
            ],
            @"cn.10086.app": @[
                @"com.chinamobile.cmcc",
                @"cn.10086.app",
            ],
            @"com.chinamobile.cmcc": @[
                @"com.chinamobile.cmcc",
                @"cn.10086.app",
            ],
            @"com.sinovatech.unicom.ui": @[
                @"com.sinovatech.unicom.ui",
                @"com.chinaunicom.mobilebusiness",
            ],
            @"com.chinaunicom.mobilebusiness": @[
                @"com.sinovatech.unicom.ui",
                @"com.chinaunicom.mobilebusiness",
            ],
            @"ctclient": @[
                @"com.chinatelecom.189client",
                @"CtClient",
            ],
            @"com.chinatelecom.bestpayclient": @[
                @"com.chinatelecom.189client",
                @"com.chinatelecom.bestpayclient",
            ],
        };
    });
    return aliases;
}

static NSString *CNDLookupMappedBundleID(NSString *base)
{
    if (base.length == 0) return nil;
    NSDictionary<NSString *, NSString *> *aliases = CNDAppIconAliases();
    NSString *mapped = aliases[base.lowercaseString];
    if (mapped.length > 0) return mapped;
    return aliases[CNDCompactAliasKey(base)];
}

NSString *CNDMappedIOSBundleIDForIconName(NSString *name, BOOL *usedAlias)
{
    if (usedAlias) *usedAlias = NO;
    if (name.length == 0) return nil;

    NSString *base = CNDIconBaseName(name);
    NSString *mapped = CNDLookupMappedBundleID(base);
    if (!mapped.length) {
        for (NSString *marker in @[@"z.", @"y."]) {
            NSRange compound = [base rangeOfString:marker options:NSBackwardsSearch];
            if (compound.location != NSNotFound && NSMaxRange(compound) < base.length) {
                NSString *tail = [base substringFromIndex:NSMaxRange(compound)];
                mapped = CNDLookupMappedBundleID(tail);
                if (mapped.length > 0) break;
            }
        }
    }
    if (mapped.length > 0) {
        if (usedAlias) *usedAlias = ![mapped isEqualToString:base];
        return mapped;
    }

    if (![base containsString:@"."]) return nil;
    return base.length > 0 ? base : nil;
}

NSArray<NSString *> *CNDMappedIOSBundleIDsForIconName(NSString *name, BOOL *usedAlias)
{
    if (usedAlias) *usedAlias = NO;
    if (name.length == 0) return @[];

    NSString *base = CNDIconBaseName(name);
    NSDictionary<NSString *, NSArray<NSString *> *> *multiAliases = CNDAppIconMultiAliases();
    NSArray<NSString *> *mapped = multiAliases[base.lowercaseString];
    if (!mapped) mapped = multiAliases[CNDCompactAliasKey(base)];
    if (mapped.count > 0) {
        if (usedAlias) {
            *usedAlias = mapped.count != 1 || ![mapped.firstObject isEqualToString:base];
        }
        return mapped;
    }

    BOOL singleUsedAlias = NO;
    NSString *single = CNDMappedIOSBundleIDForIconName(name, &singleUsedAlias);
    if (usedAlias) *usedAlias = singleUsedAlias;
    return single.length > 0 ? @[single] : @[];
}
