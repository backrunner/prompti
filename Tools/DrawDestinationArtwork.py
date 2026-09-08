#!/usr/bin/env python3
"""Original, individually drawn 64-unit destination SVGs. No external artwork.

This file is the editable source; run it to regenerate the vector asset catalog,
manifest and review gallery. Each drawing names a recognisable local subject.
"""
from pathlib import Path
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
ART = {}

def p(d, fill='none'):
    return f'<path d="{d}" fill="{fill}"/>'
def r(x,y,w,h,rx=0,fill='none'):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"/>'
def c(x,y,radius,fill='none'):
    return f'<circle cx="{x}" cy="{y}" r="{radius}" fill="{fill}"/>'
def e(x,y,rx,ry):
    return f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}"/>'
def art(key, en, zh, *shapes):
    assert key not in ART
    ART[key] = (en,zh,''.join(shapes))

# Japan: tower lattice, castle roofs, gates, clock and a yatai counter.
art('tokyo','Tokyo Tower','东京塔',
    p('M32 5V14M29 14H35L38 30L42 43L49 57H39L32 45L25 57H15L22 43L26 30Z'),
    p('M25 30H39M21 42H43M28 21H36M26 31L38 41M38 31L26 41M22 43H42'))
art('osaka','Osaka Castle','大阪城',
    p('M10 54H54L50 46H14ZM18 46V34H46V46M23 31V22H41V31M29 19V12H35V19'),
    p('M7 35Q19 32 23 27H41Q45 32 57 35ZM16 23Q25 20 28 16H36Q39 20 48 23Z'),
    p('M25 46V40M32 46V40M39 46V40M28 27V24M36 27V24M28 12L32 7L36 12'))
art('kyoto','Fushimi Inari torii','伏见稻荷鸟居',
    p('M7 13Q32 19 57 13L54 20H10ZM11 28H53M18 20L16 57M24 21L23 57M40 21L41 57M46 20L48 57M29 21V28M35 21V28'),
    p('M25 38H39M28 38V54M36 38V54'))
art('sapporo','Sapporo Clock Tower','札幌钟楼',
    p('M9 55V35L22 26V19L32 9L42 19V26L55 35V55ZM22 26H42M22 19H42M8 36H56M26 9H38'),
    c(32,25,5),p('M32 22V25L35 27M28 55V43H36V55M15 43H20M44 43H49M15 49H20M44 49H49'))
art('fukuoka','Hakata yatai stall','博多屋台',
    p('M8 24L15 12H49L56 24ZM12 24V54M52 24V54M7 40H57M17 40V54M47 40V54M23 12L21 24M41 12L43 24M32 12V24'),
    p('M13 28H26V34H13M30 34H45M32 34Q37 41 42 34M34 29V27M40 29V26M7 55H57'))
art('naha','Shureimon gate','守礼门',
    p('M7 24Q16 24 22 17H42Q48 24 57 24L54 29H10ZM14 16Q25 16 29 10H35Q39 16 50 16L47 20H17Z'),
    p('M15 29V56M21 29V56M43 29V56M49 29V56M22 36H42M26 29V35M38 29V35M12 56H24M40 56H52'),r(27,23,10,6))

# Korea: palace eaves, suspension bridge and Jeju's stone guardian.
art('seoul','Gyeongbokgung palace','景福宫',
    p('M6 29Q17 30 24 20H40Q47 30 58 29L54 35H10ZM14 18Q25 18 29 11H35Q39 18 50 18L47 22H17Z'),
    p('M13 35V54H51V35M9 58H55M18 54V41H25V54M29 54V41H35V54M39 54V41H46V54M24 24V29M40 24V29'))
art('busan','Gwangan Bridge','广安大桥',
    p('M7 45H57M17 52V13H23V52M41 52V13H47V52M8 37Q20 33 20 17Q31 38 44 17Q44 33 56 37'),
    p('M10 38V45M28 29V45M36 29V45M54 38V45M8 56Q14 52 20 56T32 56T44 56T56 56'))
art('jeju','Dol hareubang stone guardian','济州石头爷爷',
    p('M15 22Q14 6 32 6Q50 6 49 22M11 22Q32 28 53 22M18 25L20 48L17 57H47L44 48L46 25'),
    p('M32 28L28 39H35M26 45Q32 48 38 45M19 47L31 51M45 47L33 54'),c(24,31,2,'#000'),c(40,31,2,'#000'))

# China: distinctive silhouettes and local objects, rather than generic buildings.
art('beijing','Forbidden City palace roof','故宫宫殿',
    p('M6 30Q18 29 23 19H41Q46 29 58 30L54 35H10ZM14 17Q26 16 29 10H35Q38 16 50 17L47 21H17Z'),
    p('M12 35V52H52V35M7 57H57M18 38V52M25 38V52M32 38V52M39 38V52M46 38V52M18 44H46M26 25H38'))
art('shanghai','Oriental Pearl Tower','东方明珠塔',
    p('M32 5V13M30 13V20M34 13V20M29 28V37M35 28V37M27 49L21 58M37 49L43 58M31 51V58M33 51V58'),
    c(32,24,5),c(32,44,8),p('M24 44H40M13 58H51M7 56V39H15V56M49 56V32H57V56'))
art('guangzhou','Canton Tower','广州塔',
    p('M32 5V14M24 15H40Q33 32 39 56H25Q31 32 24 15ZM25 15Q40 34 25 56M39 15Q24 34 39 56M25 22H39M27 31H37M27 40H37M26 48H38M20 58H44'))
art('shenzhen','Ping An Finance Centre','平安金融中心',
    p('M20 57V22L27 13L32 5L37 13L44 22V57ZM27 13V57M37 13V57M32 17V57M20 27H44M20 47H44M15 58H49'),
    p('M9 57V38H16M48 32H55V57'))
art('chengdu','Giant panda','大熊猫',
    c(18,16,8,'#000'),c(46,16,8,'#000'),p('M11 30Q11 14 32 14Q53 14 53 30Q55 51 32 53Q9 51 11 30Z'),
    e(23,32,5,7),e(41,32,5,7),c(23,32,1.4,'#000'),c(41,32,1.4,'#000'),p('M28 41Q32 38 36 41L32 44Z','#000'),p('M25 46Q32 50 39 46'))
art('xian','Xi’an City Wall gate','西安城墙',
    p('M7 57V35H14V40H21V35H28V40H36V35H43V40H50V35H57V57M26 57V49Q32 41 38 49V57'),
    p('M17 34V24H47V34M12 24L22 18H42L52 24ZM23 17L29 11H35L41 17ZM27 26V32M37 26V32M8 48H19M45 48H56'))
art('hangzhou','Three Pools Mirroring the Moon','三潭印月',
    p('M6 53Q13 48 20 53T34 53T48 53T58 53M10 58Q17 54 24 58M38 58Q45 54 52 58'),
    p('M9 44H23L20 38V29H12V38ZM9 29L16 23L23 29ZM27 39H41L38 33V24H30V33ZM27 24L34 18L41 24ZM43 47H57L54 41V32H46V41ZM43 32L50 26L57 32Z'),c(16,34,1.5),c(34,29,1.5),c(50,37,1.5),c(49,11,5))
art('chongqing','Hongya Cave stilt houses','洪崖洞吊脚楼',
    p('M8 52V29H23V52M25 52V21H42V52M43 52V34H56V52M5 29L15 22L26 29M21 21L33 12L46 21M40 34L49 27L59 34M7 54H57M13 54V59M31 54V59M50 54V59'),
    p('M12 34H19M12 40H19M12 46H19M29 27H38M29 33H38M29 39H38M29 45H38M47 40H52M47 46H52'))

# Central Europe: each facade keeps its characteristic roof or tower profile.
art('berlin','Brandenburg Gate','勃兰登堡门',
    p('M7 25H57V31H7ZM10 21H54V25M12 31V53H18V31M24 31V53H29V31M35 31V53H40V31M46 31V53H52V31M6 57H58M26 20V14H38V20M32 14V8M24 10L32 14L40 10'))
art('munich','Frauenkirche twin domes','慕尼黑圣母教堂',
    p('M10 56V24H24V56M40 56V24H54V56M10 24Q7 13 17 10Q27 13 24 24M40 24Q37 13 47 10Q57 13 54 24M17 10V6M47 10V6M24 35L32 26L40 35M28 56V44Q32 38 36 44V56M7 57H57'),
    p('M15 31V35M19 31V35M45 31V35M49 31V35M15 43V47M19 43V47M45 43V47M49 43V47'))
art('hamburg','Elbphilharmonie','易北爱乐音乐厅',
    p('M9 53V23Q17 8 25 23Q32 30 39 19Q48 5 55 15V53ZM9 39H55M8 58Q16 54 24 58T40 58T56 58'),
    p('M16 29V35M24 30V35M32 31V35M40 27V35M48 22V35M16 45V48M24 45V48M32 45V48M40 45V48M48 45V48'))
art('frankfurt','Römer stepped gables','法兰克福罗马广场',
    p('M7 56V31H11V26H15V21H19V26H23V31H27V56M25 56V25H29V19H32V12H36V19H39V25H43V56M41 56V31H45V26H49V21H53V26H57V31V56M6 57H58'),
    p('M14 38H20M14 45H20M31 32H37M31 40H37M31 56V49H37V56M47 38H53M47 45H53'))
art('vienna','Schönbrunn Palace','美泉宫',
    p('M7 55V32H23V24L32 17L41 24V32H57V55ZM23 32H41M26 25H38M7 42H57M28 55V47H36V55M6 58H58'),
    p('M13 35V39M19 35V39M28 33V38M36 33V38M45 35V39M51 35V39M13 46V51M19 46V51M45 46V51M51 46V51M32 17V10M29 13H35'))
art('salzburg','Hohensalzburg Fortress','霍亨萨尔茨堡',
    p('M5 57Q14 47 21 48L31 41L43 46L59 57M12 44V25H22V34H28V19H39V30H47V23H55V46M12 25L17 17L22 25M28 19L33 11L39 19M47 23L51 16L55 23M17 32V38M33 25V32M44 37V42M24 42H48'))
art('zurich','Grossmünster by the Limmat','苏黎世大教堂',
    p('M12 49V23H25V49M39 49V23H52V49M12 23V16L18 10L25 16V23M39 23V16L45 10L52 16V23M25 34L32 28L39 34M29 49V41H35V49M8 53H56M7 58Q14 54 21 58T35 58T49 58'),
    p('M17 28V33M21 28V33M44 28V33M48 28V33M17 39V44M45 39V44'))
art('cologne','Cologne Cathedral','科隆大教堂',
    p('M10 57V29L18 7L26 29V57M38 57V29L46 7L54 29V57M10 29H26M38 29H54M26 34L32 27L38 34M28 57V47Q32 41 36 47V57M6 58H58'),
    p('M15 34V41M21 34V41M43 34V41M49 34V41M15 47V53M21 47V53M43 47V53M49 47V53M18 17V25M46 17V25'),c(32,37,3))

# Spain and Latin America.
art('madrid','Puerta de Alcalá','阿尔卡拉门',
    p('M7 55V28H57V55M7 28L12 22H24V17H40V22H52L57 28M24 17L32 11L40 17M12 55V39Q17 32 22 39V55M27 55V36Q32 29 37 36V55M42 55V39Q47 32 52 39V55M5 58H59'),
    p('M13 17V22M20 17V22M44 17V22M51 17V22'))
art('barcelona','Sagrada Família','圣家堂',
    p('M9 57L12 29L16 16L20 29L22 57M22 57L25 22L28 8L31 22L32 57M32 57L35 22L38 8L41 22L44 57M44 57L46 29L50 16L54 29L57 57M7 58H59'),
    p('M24 57V48Q33 35 42 48V57M15 34V39M18 45V50M28 26V31M37 26V31M49 34V39M51 45V50M31 11H25M41 11H35'))
art('seville','Plaza de España','西班牙广场',
    p('M8 51V26H17V51M47 51V26H56V51M7 26L12 11L18 26M46 26L51 11L57 26M17 38Q32 28 47 38M17 51Q32 42 47 51M22 47V39M29 44V37M36 44V37M43 47V39M7 56Q32 63 57 56M12 32V38M51 32V38'))
art('valencia','L’Hemisfèric','艺术科学城天文馆',
    p('M6 44Q18 18 40 20Q52 24 58 44ZM6 44Q31 57 58 44M12 44Q33 28 52 44M40 20L32 44M30 23L25 44M49 27L39 44M20 28L18 44M5 56H59'),
    e(32,42,8,3))
art('mexico-city','Palacio de Bellas Artes','墨西哥美术宫',
    p('M7 55V36H19V31H23Q23 17 32 14Q41 17 41 31H45V36H57V55ZM23 31H41M19 36H45M28 55V43Q32 37 36 43V55M6 58H58M32 14V8M28 11H36'),
    p('M13 41V51M20 41V51M44 41V51M51 41V51M28 21L27 29M36 21L37 29'))
art('cancun','El Rey Maya ruins and Caribbean palms','雷伊玛雅遗址与棕榈',
    p('M8 54V47H13V40H18V33H23V26H34V33H39V40H44V47H49V54ZM25 54V33H32V54M8 47H23M13 40H23M34 40H44M34 47H49'),
    p('M49 40Q52 25 49 18M49 18Q40 12 36 21M49 18Q49 6 57 8M49 18Q57 13 59 23M7 59Q22 55 36 59T57 59'))
art('buenos-aires','Obelisco','布宜诺斯艾利斯方尖碑',
    p('M25 55V17L32 6L39 17V55ZM32 6V55M21 55H43V59H21ZM28 21V26M8 52V38H19V52M45 52V32H56V52'))
art('lima','Lima Cathedral','利马主教座堂',
    p('M8 56V26H21V56M43 56V26H56V56M8 26L14 17L21 26M43 26L50 17L56 26M11 17V12H18V17M46 17V12H53V17M21 33L32 23L43 33M27 56V44Q32 36 37 44V56M6 58H58'),
    p('M13 32V38M17 32V38M47 32V38M51 32V38M32 23V16M29 19H35'),c(32,33,3))
art('santiago','San Cristóbal hill statue','圣克里斯托瓦尔山',
    p('M5 58L20 44L26 47L33 36L45 46L51 44L59 58M24 37L28 21Q32 18 36 21L40 37ZM28 22L32 27L36 22M32 27V35M25 38H39V42H25Z'),c(32,14,4),p('M7 48L13 37L21 41M43 35L49 30L57 40'))
art('bogota','Monserrate sanctuary','蒙塞拉特山圣所',
    p('M6 58L18 47L25 48L33 39L45 46L58 58M15 45V24H26V43M38 43V24H49V45M15 24L20 17L26 24M38 24L43 17L49 24M26 31L32 25L38 31M29 42V35H35V42M20 17V11M43 17V11M17 14H23M40 14H46'),
    p('M6 35L13 31M7 36L11 40L17 35L13 31'))
art('cartagena','Cartagena Clock Tower','卡塔赫纳钟楼',
    p('M7 56V39H24V26H27V17L32 8L37 17V26H40V39H57V56M24 26H40M27 17H37M12 56V48Q17 42 22 48V56M27 56V46Q32 39 37 46V56M42 56V48Q47 42 52 48V56M5 58H59'),c(32,32,4),p('M32 30V32L34 33'))
art('havana','Havana classic car','哈瓦那老爷车',
    p('M8 44V34Q8 30 14 30L20 19H39L48 29L54 31Q58 33 58 43L54 47H49M18 47H43M9 47H7V42M17 30H45M23 21L21 28M35 21L38 28M27 34H32'),
    c(14,46,6),c(48,46,6),c(14,46,2),c(48,46,2),p('M9 35H15M49 35H56M5 55H59'))
art('san-juan','El Morro sentry box','圣胡安城堡哨塔',
    p('M19 49V25H43V49L39 55H23ZM16 25Q19 19 24 17Q24 9 31 9Q38 9 38 17Q43 19 46 25ZM26 32V42H36V32ZM31 9V5M10 57H53M19 49L12 54V58M43 49L50 54V58'),
    p('M6 33L13 35M50 34L58 31'))

# English-speaking destinations and recognisable civic objects.
art('london','Tower Bridge','伦敦塔桥',
    p('M6 46H58M14 55V24H24V55M40 55V24H50V55M12 24L19 11L26 24M38 24L45 11L52 24M24 30H40M24 34H40M6 42Q15 38 19 29M58 42Q49 38 45 29M18 31V38M44 31V38M8 59Q16 55 24 59T40 59T56 59'))
art('new-york','Statue of Liberty','自由女神像',
    p('M23 51L28 30L25 25L20 14M30 29L37 30L42 48L38 51ZM23 51H42V58H21V53M35 31L44 29L46 40L39 42M31 20L29 16M35 19L36 14M38 21L42 18M28 23L24 22M29 29L38 29'),
    c(33,25,5),p('M18 14H23M18 10Q16 6 21 4Q25 9 23 10ZM19 14L20 23M15 59H49'))
art('los-angeles','Hollywood Sign','好莱坞标志',
    p('M5 49L13 43L22 44L31 39L41 41L50 38L59 43M8 56Q32 47 56 53'),
    p('M5 23V35M9 23V35M5 29H9M11 23H15V35H11ZM17 23V35H21M23 23V35H27M29 23L31 29L33 23M31 29V35M35 23L36 35L37 29L38 35L39 23M41 23H45V35H41ZM47 23H51V35H47ZM53 23V35H56L58 32V26L56 23Z').replace('/>',' stroke-width="1.4"/>'),
    p('M7 37V44M17 37V42M28 37V39M45 37V39M55 37V39'))
art('san-francisco','Golden Gate Bridge','金门大桥',
    p('M6 43L58 48M17 56V10H24V56M42 58V15H49V58M17 21H24M17 29H24M42 26H49M42 34H49M6 33Q18 26 20 14Q33 39 45 19Q51 34 58 39'),
    p('M10 31V43M30 29V45M36 31V46M55 35V48M6 58Q13 54 20 58T34 58T48 58'))
art('edinburgh','Edinburgh Castle','爱丁堡城堡',
    p('M5 58L15 47L22 49L32 41L47 47L59 58M11 46V28H17V22H25V29H32V18H43V29H53V46M32 18L37 10L43 18M17 22V17H25V22M16 35V40M22 35V40M37 25V33M46 35V41M28 44V38H35V44'))
art('dublin','Irish harp','爱尔兰竖琴',
    p('M14 12Q31 3 50 16L42 22Q39 49 23 55L17 52Q32 47 35 22L22 20L24 47L18 48ZM20 54H43V59H20Z'),
    p('M24 21L26 46M29 22V42M34 22L31 39M39 21L35 35M14 12L12 7'))
art('toronto','CN Tower','加拿大国家电视塔',
    p('M32 5V17M29 17V28M35 17V28M28 35L24 57H40L36 35M31 36V57M33 36V57M20 58H44'),
    e(32,31,11,4),p('M23 29V25H41V29M8 57V43H17V57M47 57V37H56V57'))
art('vancouver','Canada Place sails','加拿大广场帆顶',
    p('M6 47L16 18L23 47ZM19 47L31 10L38 47ZM34 47L46 17L53 47ZM49 47L57 28L60 47ZM7 51H57M8 58Q16 53 24 58T40 58T56 58'),
    p('M16 18V45M31 10V45M46 17V45'))
art('sydney','Sydney Opera House','悉尼歌剧院',
    p('M7 47H58L53 53H12ZM11 44Q12 25 10 19Q28 22 33 44ZM27 44Q28 20 31 9Q47 22 48 44ZM43 44Q49 27 59 24Q61 37 55 44Z'),
    p('M13 23L29 44M32 14L44 44M57 29L48 44M7 58Q17 54 27 58T47 58T59 58'))
art('melbourne','Melbourne W-class tram','墨尔本有轨电车',
    r(12,16,40,35,5),p('M10 24H54M12 37H52M18 51L15 58M46 51L49 58M9 58H55M23 16L32 7L41 16M26 7H38M24 25V36M40 25V36M28 39V50H36V39Z'),
    c(19,43,2),c(45,43,2))
art('singapore','Marina Bay Sands','滨海湾金沙',
    p('M7 17Q32 23 57 13L53 23Q30 30 9 24ZM14 27L11 55H21L24 28M29 29L27 55H37L39 28M44 27L44 55H54L53 25M7 59Q16 55 25 59T43 59T58 59'),
    p('M17 34L16 48M32 35L31 49M49 33V48M14 16L16 11M23 19V12M31 20L32 12'))

# Russia: onion domes, a naval spire and the city's cable-stayed bridge.
art('moscow','Saint Basil’s Cathedral','圣瓦西里大教堂',
    p('M10 56V36H23V56M26 56V28H39V56M43 56V38H55V56M10 36Q2 26 16 18Q31 27 23 36ZM26 28Q19 18 32 9Q46 18 39 28ZM43 38Q35 29 49 21Q63 29 55 38Z'),
    p('M16 18V12M32 9V4M49 21V15M14 43V49M31 35V43M48 44V51M7 58H58'))
art('saint-petersburg','Hermitage Winter Palace','冬宫博物馆',
    p('M6 55V29H24V22H40V29H58V55M6 29V24H24M40 24H58V29M24 22L32 15L40 22M9 19V24M18 19V24M46 19V24M55 19V24M27 55V45Q32 37 37 45V55M5 58H59'),
    p('M12 34V40M19 34V40M28 28V34M36 28V34M45 34V40M52 34V40M12 46V51M19 46V51M45 46V51M52 46V51'))
art('kazan','Kul Sharif Mosque','库尔谢里夫清真寺',
    p('M8 57V22L11 9L14 22V57M50 57V22L53 9L56 22V57M18 57V36H46V57M20 35Q19 24 32 16Q45 24 44 35ZM27 57V44Q32 37 37 44V57M32 16V8M7 58H57'),
    p('M18 35V28M46 35V28M7 25H15M49 25H57M23 41V49M41 41V49'))
art('sochi','Sochi Maritime Terminal','索契海港码头',
    p('M7 51V36H24V29H28V20H30L32 6L34 20H36V29H40V36H57V51M24 29H40M6 54H58M12 41V49M20 41V49M28 38V49M36 38V49M44 41V49M52 41V49M7 59Q15 55 23 59T39 59T55 59'))
art('vladivostok','Golden Bridge','金角湾大桥',
    p('M5 46H59M21 57L25 9L29 57M39 57L43 13L47 57M25 13L7 46M25 21L14 46M25 29L21 46M25 13L38 46M43 17L31 46M43 17L58 46M43 28L52 46M6 59Q14 55 22 59T38 59T54 59'))

# Other destinations: city-specific silhouettes or familiar local objects.
art('paris','Eiffel Tower','埃菲尔铁塔',
    p('M32 5V13M29 13H35L38 32L42 43L52 57H40Q32 42 24 57H12L22 43L26 32ZM24 32H40M20 43H44M26 24H38M26 33L38 42M38 33L26 42M8 58H56'))
art('rome','Colosseum','罗马斗兽场',
    p('M8 24Q31 12 56 24V49Q32 61 8 49ZM8 34Q32 44 56 34M8 43Q32 53 56 43M15 29V25Q19 21 23 25V31M28 32V27Q32 23 36 27V32M42 31V26Q46 22 50 26V29'),
    p('M15 41V36M23 44V39M31 45V40M39 44V39M48 41V36M15 51V46M24 54V49M33 55V50M42 53V48M50 50V45'))
art('amsterdam','Amsterdam canal houses','阿姆斯特丹运河屋',
    p('M7 49V27L16 18L25 27V49M24 49V22H28V17H32V11H36V17H40V22H44V49M43 49V29Q43 20 50 20Q57 20 57 29V49M6 53H58M7 59Q15 55 23 59T39 59T55 59'),
    p('M13 31V36M19 31V36M13 42V47M30 27V32M37 27V32M30 39V48H37V39ZM48 31V36M53 31V36M48 42V47'))
art('prague','Charles Bridge tower','查理大桥桥塔',
    p('M7 50H57M10 50V44Q17 35 24 44V50M27 50V42Q34 33 41 42V50M44 50V44Q51 35 58 44M20 35V22H43V35M17 22L24 8L31 22M32 22L39 8L46 22M25 27V33M37 27V33M28 35V29H34V35M6 58Q15 53 24 58T42 58T58 58'))
art('lisbon','Lisbon Tram 28','里斯本28路电车',
    r(15,18,34,35,5),p('M20 18V13H44V18M20 13L29 6H39M15 39H49M19 24H29V35H19ZM35 24H45V35H35ZM21 53L17 59M43 53L47 59M10 59H54M25 45H39'),
    c(21,45,2),c(43,45,2),p('M26 19V21H30M35 19H39V21H35'))
art('athens','Parthenon','帕特农神庙',
    p('M6 24L32 9L58 24ZM9 28H55M11 29V51H17V29M23 29V51H29V29M35 29V51H41V29M47 29V51H53V29M8 53H56M5 58H59M22 20H42'))
art('istanbul','Hagia Sophia','圣索菲亚大教堂',
    p('M7 56V26L10 13L13 26V56M51 56V26L54 13L57 26V56M17 56V39H47V56M20 34Q20 19 32 16Q44 19 44 34ZM17 39Q10 30 20 29M47 39Q54 30 44 29M27 56V45Q32 39 37 45V56M32 16V9M6 58H58'),
    p('M25 29V33M32 26V33M39 29V33M7 31H13M51 31H57'))
art('dubai','Burj Khalifa','哈利法塔',
    p('M32 4V16M28 16H35V25H39V35H44V45H49V58H16V49H21V37H25V25H28ZM32 16V58M37 36V58M43 46V58M25 39V58M12 59H53'))
art('bangkok','Wat Arun prang','郑王庙佛塔',
    p('M32 5L35 15L37 20V29L41 35V42L47 51V56H17V51L23 42V35L27 29V20L29 15ZM27 21H37M25 31H39M22 39H42M20 47H44M14 57H50M8 53V42L12 31L16 42V53M48 53V42L52 31L56 42V53'),
    p('M30 25V28M30 34V37M29 43V46M30 51V55'))
art('bali','Balinese split gate','巴厘岛善恶门',
    p('M7 57V49H10V42H13V33H17V25H21V16H27V57ZM37 57V16H43V25H47V33H51V42H54V49H57V57ZM21 16L26 7L27 16M37 16L38 7L43 16M10 49H27M13 42H27M17 33H27M37 49H54M37 42H51M37 33H47M5 59H59'))
art('honolulu','Diamond Head and surfboard','钻石头山与冲浪板',
    p('M5 48L16 31L28 24L38 29L43 40M9 48H40M8 54Q16 49 24 54T40 54T56 54M11 59Q19 55 27 59'),
    p('M48 49Q38 21 48 7Q61 18 56 47Q53 54 48 49ZM48 7L52 49M17 37L27 30L35 34'))


def main():
    source = (ROOT/'Prompti/Domain/DestinationModels.swift').read_text()
    ids = set(re.findall(r'id: "([\w-]+)", city:', source))
    ids.update(re.findall(r'\.init\("([\w-]+)", "[^"]+", "[^"]+", -?\d', source))
    assert set(ART)==ids, f'Coverage mismatch: missing {ids-set(ART)}, extra {set(ART)-ids}'
    output = ROOT/'Prompti/Assets.xcassets/Destinations'
    output.mkdir(exist_ok=True)
    (output/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}},indent=2)+'\n')
    manifest=[]
    for key,(en,zh,shapes) in ART.items():
        folder=output/f'Destination-{key}.imageset'; folder.mkdir(exist_ok=True)
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><title>{html.escape(en)}</title><g fill="none" stroke="#000" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">{shapes}</g></svg>\n'
        (folder/f'{key}.svg').write_text(svg)
        (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':f'{key}.svg','idiom':'universal'}],'info':{'author':'xcode','version':1},'properties':{'preserves-vector-representation':True,'template-rendering-intent':'template'}},indent=2)+'\n')
        manifest.append({'id':key,'subject':en,'subject_zh':zh,'asset':str((folder/f'{key}.svg').relative_to(ROOT))})
    docs=ROOT/'Documentation/Brand/DestinationArtwork';docs.mkdir(exist_ok=True)
    (docs/'manifest.json').write_text(json.dumps({'source':'Tools/DrawDestinationArtwork.py','license':'Original Prompti artwork; repository license','viewBox':'0 0 64 64','count':len(ART),'destinations':manifest},ensure_ascii=False,indent=2)+'\n')
    cells=[]
    for entry in manifest:
        key=entry['id'];svg=(ROOT/entry['asset']).read_text()
        cells.append(f'<article><div class="art">{svg}</div><b>{html.escape(key)}</b><span>{html.escape(entry["subject_zh"])}</span><small>{html.escape(entry["subject"])}</small></article>')
    (docs/'Gallery.html').write_text('''<!doctype html><html lang="zh-Hans"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Prompti · 目的地 SVG 图稿</title><style>
:root{color-scheme:light dark}*{box-sizing:border-box}body{margin:0;padding:40px;background:#f5f6f0;color:#173d33;font:15px -apple-system,BlinkMacSystemFont,sans-serif}h1{font-size:26px;margin:0 0 8px}p{color:#52675b;margin:0 0 28px}main{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:16px}article{text-align:center;background:#fff;border:1px solid #d8e3d8;border-radius:20px;padding:18px 8px}.art{width:80px;height:80px;display:grid;place-items:center;margin:0 auto 12px;background:#eaf0e6;border-radius:14px}.art svg{width:64px;height:64px}.art g{stroke:#08765d}.art [fill="#000"]{fill:#08765d}b,span,small{display:block}b{font-size:12px;margin-bottom:6px}small{font-size:11px;color:#52675b;margin-top:4px}@media(prefers-color-scheme:dark){body{background:#101c18;color:#edf4eb}p,small{color:#b2c5b7}article{background:#1a2a24;border-color:#324d3e}.art{background:#263b32}.art g{stroke:#a3f2ce}.art [fill="#000"]{fill:#a3f2ce}}@media(max-width:700px){main{grid-template-columns:repeat(3,1fr)}body{padding:20px}}
</style><h1>65 个目的地，65 幅独立 SVG</h1><p>原始矢量图稿审阅页 · 不是 App 截图。每幅图保留当地地标或代表物的轮廓，浅深色由语义色着色。</p><main>'''+''.join(cells)+'</main></html>\n')
    print(f'Generated {len(ART)} original vector assets and the review gallery.')

if __name__=='__main__': main()
