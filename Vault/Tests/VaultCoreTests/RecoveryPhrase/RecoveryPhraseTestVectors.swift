// Generated test vectors. Do not edit by hand.
//
// BIP39: `vectors.json` from trezor/python-mnemonic at b57a5ad77a981e743f4167ab2f7927a55c1e82a8, plus 15 and
// 21 word phrases created with `Mnemonic(language).to_mnemonic(entropy)` from the same commit, using
// `random.Random(39)` entropy. Invalid phrases swap two words and are confirmed invalid by `Mnemonic.check`.
// SLIP-39: `vectors.json` from trezor/python-shamir-mnemonic at 17fcce14736afe498871d3018e4fa9330443471a, with
// each share classified by `Share.from_mnemonic`.
// Electrum: `tests/test_mnemonic.py` from spesmilo/electrum at 638fbba8ff0c449b773f2fe3d3d06b984491e8fa.
// Monero: `tests/functional_tests/transfer.py` from monero-project/monero at d1bcbc76713be3905360d0d49f8cad0cd00d52e1.

import VaultCore

enum RecoveryPhraseTestVectors {
    /// Valid BIP39 phrases, with the language of their wordlist. Japanese phrases use ideographic spaces.
    static let bip39Valid: [(BIP39Language, String)] = [
        (.english, "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"),
        (.english, "legal winner thank year wave sausage worth useful legal winner thank yellow"),
        (.english, "letter advice cage absurd amount doctor acoustic avoid letter advice cage above"),
        (.english, "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong"),
        (
            .english,
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent",
        ),
        (
            .english,
            "legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal will",
        ),
        (
            .english,
            "letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter always",
        ),
        (.english, "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo when"),
        (
            .english,
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art",
        ),
        (
            .english,
            "legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth title",
        ),
        (
            .english,
            "letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic bless",
        ),
        (.english, "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"),
        (.english, "ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic"),
        (
            .english,
            "gravity machine north sort system female filter attitude volume fold club stay feature office ecology stable narrow fog",
        ),
        (
            .english,
            "hamster diagram private dutch cause delay private meat slide toddler razor book happy fancy gospel tennis maple dilemma loan word shrug inflict delay length",
        ),
        (.english, "scheme spot photo card baby mountain device kick cradle pact join borrow"),
        (
            .english,
            "horn tenant knee talent sponsor spell gate clip pulse soap slush warm silver nephew swap uncle crack brave",
        ),
        (
            .english,
            "panda eyebrow bullet gorilla call smoke muffin taste mesh discover soft ostrich alcohol speed nation flash devote level hobby quick inner drive ghost inside",
        ),
        (.english, "cat swing flag economy stadium alone churn speed unique patch report train"),
        (
            .english,
            "light rule cinnamon wrap drastic word pride squirrel upgrade then income fatal apart sustain crack supply proud access",
        ),
        (
            .english,
            "all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform",
        ),
        (.english, "vessel ladder alter error federal sibling chat ability sun glass valve picture"),
        (
            .english,
            "scissors invite lock maple supreme raw rapid void congress muscle digital elegant little brisk hair mango congress clump",
        ),
        (
            .english,
            "void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold",
        ),
        (.english, "crystal basic light give main tail divorce cruise slush aspect finger heart tent trend borrow"),
        (
            .english,
            "entry grow invite caution south asset ramp collect skull absorb daring simple deer change barrel timber install improve gospel pioneer april",
        ),
        (.japanese, "あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あおぞら"),
        (.japanese, "そつう　れきだい　ほんやく　わかす　りくつ　ばいか　ろせん　やちん　そつう　れきだい　ほんやく　わかめ"),
        (.japanese, "そとづら　あまど　おおう　あこがれる　いくぶん　けいけん　あたえる　いよく　そとづら　あまど　おおう　あかちゃん"),
        (.japanese, "われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　ろんぶん"),
        (
            .japanese,
            "あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あらいぐま",
        ),
        (.japanese, "そつう　れきだい　ほんやく　わかす　りくつ　ばいか　ろせん　やちん　そつう　れきだい　ほんやく　わかす　りくつ　ばいか　ろせん　やちん　そつう　れいぎ"),
        (.japanese, "そとづら　あまど　おおう　あこがれる　いくぶん　けいけん　あたえる　いよく　そとづら　あまど　おおう　あこがれる　いくぶん　けいけん　あたえる　いよく　そとづら　いきなり"),
        (.japanese, "われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　りんご"),
        (
            .japanese,
            "あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　いってい",
        ),
        (
            .japanese,
            "そつう　れきだい　ほんやく　わかす　りくつ　ばいか　ろせん　やちん　そつう　れきだい　ほんやく　わかす　りくつ　ばいか　ろせん　やちん　そつう　れきだい　ほんやく　わかす　りくつ　ばいか　ろせん　まんきつ",
        ),
        (
            .japanese,
            "そとづら　あまど　おおう　あこがれる　いくぶん　けいけん　あたえる　いよく　そとづら　あまど　おおう　あこがれる　いくぶん　けいけん　あたえる　いよく　そとづら　あまど　おおう　あこがれる　いくぶん　けいけん　あたえる　うめる",
        ),
        (.japanese, "われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　われる　らいう"),
        (.japanese, "ておくれ　げざん　しねま　こりる　きぼう　しねん　ななおし　ほんやく　きない　けむり　けまり　てんない"),
        (.japanese, "しはつ　たいちょう　ちめいど　ひりつ　ほくろ　こやく　こんかい　いひん　よろしい　さくら　がはく　ふっかつ　こまる　つごう　けぬき　ふすま　ちから　さくし"),
        (
            .japanese,
            "しやくしょ　くちこみ　どんぶり　けつじょ　おとしもの　くうぐん　どんぶり　たずさわる　ひたむき　みうち　にほん　うわさ　しゃけん　このよ　じどう　ほめる　たいよう　くふう　そんちょう　ろくが　はんこ　せあぶら　くうぐん　そっこう",
        ),
        (.japanese, "はいち　ふかい　てんすう　おさない　いろえんぴつ　だんち　くださる　せんちょう　きさらぎ　てきとう　せもたれ　うんどう"),
        (.japanese, "すいえい　ほとんど　せんやく　ほしい　ふうふ　ひんそう　ざんしょ　がちょう　なにわ　ひはん　ひつじゅひん　られつ　はんぼうき　ちそう　ほいく　めだつ　きさま　えがお"),
        (
            .japanese,
            "てそう　こつこつ　えんちょう　じてん　おおや　ぴっちり　だんねつ　ほそく　たなばた　くらべる　ひまん　ていき　あんい　ひんしゅ　ちきん　ざいげん　くたびれる　そなえる　しんか　にいがた　せきむ　けしょう　しあさって　せたい",
        ),
        (.japanese, "おたく　ほうりつ　さいかい　げねつ　ふせい　いいだす　かいてん　ひんしゅ　もえる　てのひら　ねいき　むいか"),
        (.japanese, "そむく　のぞく　かいふく　ろてん　げきやく　ろくが　ともだち　ふじみ　やおや　まかせる　すらすら　こぼれる　いぜん　へんたい　きさま　へきが　なたでここ　あさひ"),
        (
            .japanese,
            "あんぜん　すうじつ　たいふう　こんぽん　そこそこ　こたつ　しんせいじ　あんこ　うしなう　しまる　じどう　そうり　てはい　ていし　おめでとう　たんまつ　せんげん　たおる　ぬめり　このまま　ひいき　あまい　のらねこ　にんそう",
        ),
        (.japanese, "ようきゅう　そあく　いきおい　こうつう　こもじ　はんだん　おんしゃ　あいさつ　へいたく　しすう　ゆうびんきょく　てんぷら"),
        (.japanese, "はえる　せっさたくま　そんみん　たいよう　へこむ　になう　にっさん　よゆう　きあつ　だんぼう　くねくね　けらい　そんけい　えほうまき　しゃうん　たいむ　きあつ　かぶか"),
        (
            .japanese,
            "よゆう　かんけい　けぶかい　へいこう　おかず　べんごし　りえき　じゆう　はんい　ともる　かほご　きぬごし　つみき　いきる　はかる　てふだ　しほう　ひろう　とくてん　ほったん　こさめ　ひつじゅひん　せつぞく　めんどう",
        ),
        (.japanese, "あきる　ひはん　せのび　うぶげ　じだい　せたけ　せんやく　ふすま　せんやく　らくがき　かいぞうど　はづき　ふっき　せんきょ　くつした"),
        (.japanese, "りえき　けしき　むなしい　にもつ　てれび　けちゃっぷ　ねだん　けとる　こうてい　そうなん　ずっしり　ちあん　ぴったり　さいせい　めいうん　さずかる　うわき　かんそう　れんさい　せぼね　むえき"),
        (.korean, "가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가능"),
        (.korean, "실장 활동 큰절 흔적 형제 제대로 훈련 한글 실장 활동 큰절 흔히"),
        (.korean, "실현 감소 기법 가상 걱정 무슨 가족 공간 실현 감소 기법 가득"),
        (.korean, "힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 흑백"),
        (.korean, "가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 강도"),
        (.korean, "실장 활동 큰절 흔적 형제 제대로 훈련 한글 실장 활동 큰절 흔적 형제 제대로 훈련 한글 실장 환갑"),
        (.korean, "실현 감소 기법 가상 걱정 무슨 가족 공간 실현 감소 기법 가상 걱정 무슨 가족 공간 실현 거액"),
        (.korean, "힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 화살"),
        (.korean, "가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 계단"),
        (.korean, "실장 활동 큰절 흔적 형제 제대로 훈련 한글 실장 활동 큰절 흔적 형제 제대로 훈련 한글 실장 활동 큰절 흔적 형제 제대로 훈련 통로"),
        (.korean, "실현 감소 기법 가상 걱정 무슨 가족 공간 실현 감소 기법 가상 걱정 무슨 가족 공간 실현 감소 기법 가상 걱정 무슨 가족 구속"),
        (.korean, "힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 힘껏 허용"),
        (.korean, "원고 물질 생일 부산 마요네즈 생활 일찍 큰절 동화책 반성 반드시 의식"),
        (.korean, "서비스 알코올 오로지 착각 카운터 부근 부정 고양이 허락 비디오 단맛 체온 본인 완전 바람 철학 영하 비닐"),
        (.korean, "설렁탕 모범 일곱 민간 낙엽 매스컴 일곱 언어 지진 통장 잠시 국제 설문 복도 생방송 큰딸 약수 목소리 아직 횡단보도 중독 수필 매스컴 실컷"),
        (.korean, "제주도 처음 의견 김밥 공부 연출 모델 시장 대합실 원래 시금치 군인"),
        (.korean, "소음 큰길 식당 커튼 책임 창구 사흘 다양성 일행 질병 진급 혈액 증가 예산 치약 하룻밤 대한민국 그날"),
        (.korean, "월급 보너스 금고 생물 기분 진리 열매 콘서트 에어컨 몸무게 집중 우체국 강제 창고 영혼 분필 모든 심리 소나기 자랑 순서 미디어 삼십 술집"),
        (.korean, "나들이 침대 분야 바이러스 첫날 개선 논문 창고 하필 윗사람 저고리 팩스"),
        (.korean, "씨름 정도 놀이 훨씬 물결 횡단보도 인천 철저히 학비 킬로 수염 본격적 결심 취업 대한민국 출연 일정 가운데"),
        (.korean, "개구리 속담 액수 북한 실내 병아리 소망 같이 관찰 선물 생방송 신용 유난히 운반 남대문 열차 시설 양주 재판 보편적 증세 감기 정오 장미"),
        (.korean, "해결 식초 거실 백성 볼펜 중세 냄새 가끔 출근 상인 한번 의심"),
        (.korean, "제한 스위치 아프리카 약수 출입 잠수함 잔디 향상 당장 열정 목록 반장 아시아 그토록 선풍기 약간 당장 단순"),
        (.korean, "향상 담배 박수 추측 기술 충분히 협력 성적 줄무늬 인체 단위 딸아이 왼손 거짓 조깅 유명 석사 참석 이야기 크림 변동 진급 스케이트 하지만"),
        (.korean, "시부모 중부 산책 단체 위험 각오 패션 부동산 세상 고집 패션 냉면 시점 대부분 지출"),
        (.korean, "기억 초청 손질 지극히 발바닥 벨트 타자기 창문 쇠고기 농부 태풍 중부 캐릭터 근원 센터 사전 저녁 포스터 상상 단풍 충고"),
        (.spanish, "ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco abierto"),
        (.spanish, "ligero vista talar yogur venta queso yacer trozo ligero vista talar zafiro"),
        (.spanish, "lino admitir bolero abrir álbum dejar acelga aprender lino admitir bolero abogado"),
        (.spanish, "zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo yodo"),
        (
            .spanish,
            "ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco afición",
        ),
        (
            .spanish,
            "ligero vista talar yogur venta queso yacer trozo ligero vista talar yogur venta queso yacer trozo ligero violín",
        ),
        (
            .spanish,
            "lino admitir bolero abrir álbum dejar acelga aprender lino admitir bolero abrir álbum dejar acelga aprender lino alacrán",
        ),
        (
            .spanish,
            "zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo viejo",
        ),
        (
            .spanish,
            "ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ancla",
        ),
        (
            .spanish,
            "ligero vista talar yogur venta queso yacer trozo ligero vista talar yogur venta queso yacer trozo ligero vista talar yogur venta queso yacer teatro",
        ),
        (
            .spanish,
            "lino admitir bolero abrir álbum dejar acelga aprender lino admitir bolero abrir álbum dejar acelga aprender lino admitir bolero abrir álbum dejar acelga aumento",
        ),
        (
            .spanish,
            "zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo zurdo varón",
        ),
        (.spanish, "obra diadema gorila farmacia colgar gorra pausa talar cocina duda dragón optar"),
        (
            .spanish,
            "gráfico madera muro rutina suelo falso favor añadir variar firma casco semana fácil neón don sección morder fingir",
        ),
        (
            .spanish,
            "guion culebra parcela diluir buitre crecer parcela marzo roce tejado picar azafrán guitarra exilio goloso tabla mando curar loco voto reparto insecto crecer lince",
        ),
        (.spanish, "ración sapo opción brinco árbol mismo cueva lamer cigarro obrero júpiter azufre"),
        (
            .spanish,
            "honor tabique lata sultán sanidad salón gafas carga payaso rostro rojizo vena retrato móvil soplar trabajo cifra balde",
        ),
        (
            .spanish,
            "océano eterno bestia golfo bomba ron moda sur médula danza rueda núcleo agrio salmón morir ficha cuidar linterna higiene pensar iris diario ganso jamón",
        ),
        (.spanish, "bucle sótano fibra donar seco aire campo salmón trato odio poco tierra"),
        (
            .spanish,
            "llaga pudor candil yate detalle voto papá saxofón tribu talla infiel exponer altivo sonoro cifra solapa pata abuso",
        ),
        (
            .spanish,
            "águila hoyo maldad fértil libertad estilo historia agudo asilo grosor goloso leopardo odisea nueve butaca molde lacio mañana plomo exento rey adicto puño piña",
        ),
        (.spanish, "urbe lección ajuste enero faena reptil caimán abdomen sobre genio túnel óptica"),
        (
            .spanish,
            "rama jeringa logro mando soldado pezuña pésimo vampiro cerrar mojar cupón dueño llover barro guerra mambo cerrar casero",
        ),
        (
            .spanish,
            "vampiro célula dos simio bono sondeo vencer haz remar papel castor codo nivel alarma rapaz ofensa gripe sagaz otro tabaco esfuerzo rojizo jinete traje",
        ),
        (
            .spanish,
            "repetir tope corcho rotar milagro deporte boca polen tabla puño octubre vehículo antena grasa faena",
        ),
        (
            .spanish,
            "bufanda humano riqueza poner buitre museo cambio tiempo mirar malo rubor azúcar ogro fábula lujo punto baño fobia limpio rama tinta",
        ),
        (.chineseSimplified, "的 的 的 的 的 的 的 的 的 的 的 在"),
        (.chineseSimplified, "枪 疫 霉 尝 俩 闹 饿 贤 枪 疫 霉 卿"),
        (.chineseSimplified, "壤 对 据 人 三 谈 我 表 壤 对 据 不"),
        (.chineseSimplified, "歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 逻"),
        (.chineseSimplified, "的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 动"),
        (.chineseSimplified, "枪 疫 霉 尝 俩 闹 饿 贤 枪 疫 霉 尝 俩 闹 饿 贤 枪 殿"),
        (.chineseSimplified, "壤 对 据 人 三 谈 我 表 壤 对 据 人 三 谈 我 表 壤 民"),
        (.chineseSimplified, "歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 裕"),
        (.chineseSimplified, "的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 性"),
        (.chineseSimplified, "枪 疫 霉 尝 俩 闹 饿 贤 枪 疫 霉 尝 俩 闹 饿 贤 枪 疫 霉 尝 俩 闹 饿 搭"),
        (.chineseSimplified, "壤 对 据 人 三 谈 我 表 壤 对 据 人 三 谈 我 表 壤 对 据 人 三 谈 我 五"),
        (.chineseSimplified, "歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 佳"),
        (.chineseSimplified, "蒙 台 脱 纪 构 硫 浆 霉 感 仅 鱼 汤"),
        (.chineseSimplified, "父 泥 炼 胁 鞋 控 载 政 惨 逐 整 碗 环 惯 案 棒 订 移"),
        (.chineseSimplified, "宁 照 违 材 交 养 违 野 悉 偷 梅 设 贵 帝 鲜 仰 圈 首 荷 钩 隙 抓 养 熟"),
        (.chineseSimplified, "伐 旱 泡 口 线 揭 县 杨 断 芳 额 件"),
        (.chineseSimplified, "福 惜 怀 叔 筋 酵 货 科 牙 冒 辈 罩 悬 耕 浇 呵 连 级"),
        (.chineseSimplified, "仪 未 九 茶 队 梯 妇 孤 托 病 泉 贺 产 绘 吹 测 局 碳 征 墨 晶 帮 息 延"),
        (.chineseSimplified, "济 扶 块 言 穗 定 万 绘 姻 逃 颗 焰"),
        (.chineseSimplified, "虑 铺 目 祸 英 钩 尤 添 醇 嘛 触 独 起 赋 连 剪 邦 中"),
        (.chineseSimplified, "而 怕 夏 客 盖 古 松 面 解 谓 鲜 唯 障 烯 共 吴 永 丁 赤 副 醒 分 猛 埔"),
        (.chineseSimplified, "昏 途 所 够 请 乃 风 一 雕 缺 垫 阀"),
        (.chineseSimplified, "瓶 顾 床 圈 倡 励 炭 柄 且 招 价 紧 折 将 乎 硬 且 空"),
        (.chineseSimplified, "柄 需 固 姆 色 斥 霍 握 宾 琴 况 团 抵 经 摸 郭 沙 鸣 拖 妙 阳 辈 掉 迁"),
        (.chineseSimplified, "衡 臣 酵 请 举 务 铺 宜 你 泰 津 口 削 排 损"),
        (.chineseSimplified, "棋 炉 剂 占 珍 午 甲 暂 擦 讼 跳 附 酸 科 余 汉 味 紧 出 礼 仰"),
        (.chineseTraditional, "的 的 的 的 的 的 的 的 的 的 的 在"),
        (.chineseTraditional, "槍 疫 黴 嘗 倆 鬧 餓 賢 槍 疫 黴 卿"),
        (.chineseTraditional, "壤 對 據 人 三 談 我 表 壤 對 據 不"),
        (.chineseTraditional, "歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 邏"),
        (.chineseTraditional, "的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 動"),
        (.chineseTraditional, "槍 疫 黴 嘗 倆 鬧 餓 賢 槍 疫 黴 嘗 倆 鬧 餓 賢 槍 殿"),
        (.chineseTraditional, "壤 對 據 人 三 談 我 表 壤 對 據 人 三 談 我 表 壤 民"),
        (.chineseTraditional, "歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 裕"),
        (.chineseTraditional, "的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 的 性"),
        (.chineseTraditional, "槍 疫 黴 嘗 倆 鬧 餓 賢 槍 疫 黴 嘗 倆 鬧 餓 賢 槍 疫 黴 嘗 倆 鬧 餓 搭"),
        (.chineseTraditional, "壤 對 據 人 三 談 我 表 壤 對 據 人 三 談 我 表 壤 對 據 人 三 談 我 五"),
        (.chineseTraditional, "歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 歇 佳"),
        (.chineseTraditional, "蒙 台 脫 紀 構 硫 漿 黴 感 僅 魚 湯"),
        (.chineseTraditional, "父 泥 煉 脅 鞋 控 載 政 慘 逐 整 碗 環 慣 案 棒 訂 移"),
        (.chineseTraditional, "寧 照 違 材 交 養 違 野 悉 偷 梅 設 貴 帝 鮮 仰 圈 首 荷 鉤 隙 抓 養 熟"),
        (.chineseTraditional, "伐 旱 泡 口 線 揭 縣 楊 斷 芳 額 件"),
        (.chineseTraditional, "福 惜 懷 叔 筋 酵 貨 科 牙 冒 輩 罩 懸 耕 澆 呵 連 級"),
        (.chineseTraditional, "儀 未 九 茶 隊 梯 婦 孤 托 病 泉 賀 產 繪 吹 測 局 碳 徵 墨 晶 幫 息 延"),
        (.chineseTraditional, "濟 扶 塊 言 穗 定 萬 繪 姻 逃 顆 焰"),
        (.chineseTraditional, "慮 鋪 目 禍 英 鉤 尤 添 醇 嘛 觸 獨 起 賦 連 剪 邦 中"),
        (.chineseTraditional, "而 怕 夏 客 蓋 古 松 面 解 謂 鮮 唯 障 烯 共 吳 永 丁 赤 副 醒 分 猛 埔"),
        (.chineseTraditional, "昏 途 所 夠 請 乃 風 一 雕 缺 墊 閥"),
        (.chineseTraditional, "瓶 顧 床 圈 倡 勵 炭 柄 且 招 價 緊 折 將 乎 硬 且 空"),
        (.chineseTraditional, "柄 需 固 姆 色 斥 霍 握 賓 琴 況 團 抵 經 摸 郭 沙 鳴 拖 妙 陽 輩 掉 遷"),
        (.chineseTraditional, "楊 錐 凝 力 柴 堡 圖 講 遭 紗 悟 衣 央 宜 的"),
        (.chineseTraditional, "擺 牌 黎 爹 損 罰 繞 勝 哀 屆 決 易 吞 警 第 堡 加 柳 半 托 細"),
        (
            .french,
            "abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abeille",
        ),
        (.french, "implorer visage sonnette voyage véloce pourpre volaille tribunal implorer visage sonnette voyelle"),
        (.french, "indexer acompte bolide abrasif agréable dédale abusif appuyer indexer acompte bolide abolir"),
        (
            .french,
            "zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie voter",
        ),
        (
            .french,
            "abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser adéquat",
        ),
        (
            .french,
            "implorer visage sonnette voyage véloce pourpre volaille tribunal implorer visage sonnette voyage véloce pourpre volaille tribunal implorer vinaigre",
        ),
        (
            .french,
            "indexer acompte bolide abrasif agréable dédale abusif appuyer indexer acompte bolide abrasif agréable dédale abusif appuyer indexer agencer",
        ),
        (
            .french,
            "zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie viande",
        ),
        (
            .french,
            "abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser anaphore",
        ),
        (
            .french,
            "implorer visage sonnette voyage véloce pourpre volaille tribunal implorer visage sonnette voyage véloce pourpre volaille tribunal implorer visage sonnette voyage véloce pourpre volaille studieux",
        ),
        (
            .french,
            "indexer acompte bolide abrasif agréable dédale abusif appuyer indexer acompte bolide abrasif agréable dédale abusif appuyer indexer acompte bolide abrasif agréable dédale abusif axiome",
        ),
        (
            .french,
            "zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie zoologie valable",
        ),
        (
            .french,
            "monument dépenser féroce entasser comédie ferveur optique sonnette codifier discuter dioxyde nerveux",
        ),
        (
            .french,
            "fiasco ivoire mardi révulsif signal enlever envahir anormal vaisseau essayer céleste sagesse engager mener différer ruisseau lutter esprit",
        ),
        (
            .french,
            "flatteur cultiver oisillon destrier brusque crainte oisillon labourer remède substrat parfumer banquier flèche enclave fémur sombre jongler damier insigne voguer rasage gomme crainte incendie",
        ),
        (.french, "prélude routine négation brasier arlequin logique cuivre hiberner cirque moqueur halte barque"),
        (
            .french,
            "froid soluble horde sinistre rouge rocheux exiler causer orbite résineux renfort vaste récolter maison serrure tonique cirer bélier",
        ),
        (
            .french,
            "mouche embryon bison femme bondir renvoi louer social largeur déborder rétablir miracle adresse rivière machine époque culminer indice frégate ouvrage gourmand déposer exulter grappin",
        ),
        (.french, "brochure sextuple épisode digérer ruser affecter cantine rivière torse muscle permuter talisman"),
        (
            .french,
            "informer poivre capable volcan dénicher voguer offenser ruiner tragique sortir glace enduire allouer serein cirer semaine opportun abriter",
        ),
        (
            .french,
            "adverbe fuite jaune épaule imbiber éluder frémir adulte attentif filou fémur idylle muséum mobile bureau loyal hélium jugement péplum encadrer rédiger acier posséder pavillon",
        ),
        (.french, "ultrason hublot agacer éclore englober ravin caféine abandon séduire farfelu tropical nettoyer"),
        (
            .french,
            "prétexte grogner instinct jongler sembler paresse papier vaillant chenille louve cynique dissiper inoculer besogne flairer jeunesse chenille cellule",
        ),
        (
            .french,
            "vaillant chance dimanche sécable bonus séparer vecteur forcer raideur officier censurer cohésion meuble agiter prison mutation filière rincer novice solitude élargir renfort gronder tornade",
        ),
        (
            .french,
            "dissiper jongler adjuger subtil donjon agrafer machine auberge blinder ancien maléfice libérer cloporte novembre dynastie",
        ),
        (
            .french,
            "berger innocent couvrir loterie copie limonade mairie cribler atelier séquence anarchie dégager labial mobile mesure ferveur devoir abaisser bonus aliéner prodige",
        ),
        (.italian, "abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abete"),
        (.italian, "mimosa vita sussurro zinco vero saltare zattera ulisse mimosa vita sussurro zircone"),
        (.italian, "misurare afoso bravura accadere alogeno dottore acrilico arazzo misurare afoso bravura abisso"),
        (.italian, "zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zerbino"),
        (
            .italian,
            "abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco agitare",
        ),
        (
            .italian,
            "mimosa vita sussurro zinco vero saltare zattera ulisse mimosa vita sussurro zinco vero saltare zattera ulisse mimosa virulento",
        ),
        (
            .italian,
            "misurare afoso bravura accadere alogeno dottore acrilico arazzo misurare afoso bravura accadere alogeno dottore acrilico arazzo misurare allievo",
        ),
        (
            .italian,
            "zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa vile",
        ),
        (
            .italian,
            "abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco angelo",
        ),
        (
            .italian,
            "mimosa vita sussurro zinco vero saltare zattera ulisse mimosa vita sussurro zinco vero saltare zattera ulisse mimosa vita sussurro zinco vero saltare zattera tarpare",
        ),
        (
            .italian,
            "misurare afoso bravura accadere alogeno dottore acrilico arazzo misurare afoso bravura accadere alogeno dottore acrilico arazzo misurare afoso bravura accadere alogeno dottore acrilico baco",
        ),
        (
            .italian,
            "zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa zuppa vedetta",
        ),
        (.italian, "pesista educare imballo formica curvo imbevuto raddoppio sussurro croce eppure epilogo poligono"),
        (
            .italian,
            "immolato mummia oviparo sigla stirpe fonetico fosso appetito vasca galoppo cigno solubile foderato pargolo enduro sociale ormeggio galateo",
        ),
        (
            .italian,
            "infatti dire pudica elica camola deposito pudica nobile servire taverna restauro baritono inflitto flacone ilare suonare nastrare dito montato vulcano scrutinio lisca deposito mirtillo",
        ),
        (.italian, "sarto smottato podismo burlone aria omissione dipolo marmo coricato peso malto basso"),
        (
            .italian,
            "italia sultano meccanico strappo smeraldo sipario gommone chimera raffica sforzato sfamato vendemmia segnalato oscurare staffa trio cordata benda",
        ),
        (
            .italian,
            "piacere feudo bisonte ignorato brevetto sfida onorevole stufo nulla docente sfuso perbene albo sinusoide orologio fulmine diradare mitezza iride rata londra egoismo gravoso luce",
        ),
        (.italian, "calmo statuto fucsia energia sodale aliante cedibile sinusoide trovare pila rinnovo tiro"),
        (
            .italian,
            "modulo rubizzo cefalo zavorra economia vulcano prudente soccorso tuta svedese limitare fluente amico srotolato cordata sportivo querela accusato",
        ),
        (
            .italian,
            "alcolico lacrima muto frigo michele fessura irrigato alce ateismo incendio ilare metallo pilifero pergamena canotto opposto manovra nemmeno rimorchio fisico selettivo aforisma sabotato riciclato",
        ),
        (.italian, "utopia melodia allegro evoluto folata scuola carisma abbaglio spillato guanto unificato pollice"),
        (
            .italian,
            "satira lusinga mordere nastrare sposo responso replica varcato colza opinione distanza erario monetario bici india narice colza cilindro",
        ),
        (
            .italian,
            "varcato codice enzima spessore brillante squillo vento insieme scoprire prugna circa cruciale peccato allusivo savio pilota inarcare simulato precluso sugo fegato sfamato lusso trono",
        ),
        (
            .italian,
            "agevole sbattere pronome lesto scuola parvenza milano emesso lupo tentacolo digitale lutto crusca clinica spalla",
        ),
        (
            .italian,
            "lilla vipera clinica castello rollio salivare emblema gonna statuto azzimo chitarra roba verbale conciso mimosa cocco allegro sussurro gennaio sfarzoso folata",
        ),
        (
            .czech,
            "abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace agrese",
        ),
        (.czech, "obrazec znak uznat zubovina zeman skupina zrcadlo vzchopit obrazec znak uznat zubr"),
        (.czech, "obvinit bageta doma amputace bidlo jedle arogance butik obvinit bageta doma akce"),
        (.czech, "zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zticha"),
        (
            .czech,
            "abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace balonek",
        ),
        (
            .czech,
            "obrazec znak uznat zubovina zeman skupina zrcadlo vzchopit obrazec znak uznat zubovina zeman skupina zrcadlo vzchopit obrazec zmije",
        ),
        (
            .czech,
            "obvinit bageta doma amputace bidlo jedle arogance butik obvinit bageta doma amputace bidlo jedle arogance butik obvinit bezinka",
        ),
        (.czech, "zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zlehka"),
        (
            .czech,
            "abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace branka",
        ),
        (
            .czech,
            "obrazec znak uznat zubovina zeman skupina zrcadlo vzchopit obrazec znak uznat zubovina zeman skupina zrcadlo vzchopit obrazec znak uznat zubovina zeman skupina zrcadlo veskrze",
        ),
        (
            .czech,
            "obvinit bageta doma amputace bidlo jedle arogance butik obvinit bageta doma amputace bidlo jedle arogance butik obvinit bageta doma amputace bidlo jedle arogance cihla",
        ),
        (
            .czech,
            "zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zvyk zavolat",
        ),
        (.czech, "pokoj jogurt malovat kroupa holub malvice rachot uznat hnout kasa karamel potupa"),
        (
            .czech,
            "masakr odtok pijavice tajga upravit krmelec krvinka buditel zavinit lakomec flirt traktor kresba plevel kapitola tlupa paseka ladnost",
        ),
        (
            .czech,
            "migrace iluze pukavec kaktus drogerie hrobka pukavec onehdy suchar veterina rorejs cukr mihule koza makovice uvozovka oklika inzerce odhadce zprudka spousta namluvit hrobka obsluha",
        ),
        (.czech, "sledovat ticho potkan dotaz carevna pahorek ihned nikterak hematom pokrok neochota cvik"),
        (
            .czech,
            "most uvolnit novota usmrtit terapie tehdy litovat filozof radon svrab surovina zdivo stanice pejsek ukrojit vymizet helma decibel",
        ),
        (
            .czech,
            "poloha koruna dobytek makak domluvit svatba paluba utahovat orlice jakost sypat podvod barva technika pastelka kurt ikona obvod mokro recept napnout kabel lord nasadit",
        ),
        (.czech, "drak uniforma kuna kapka tmel bedna evoluce technika vypustit popadat rychlost vodstvo"),
        (
            .czech,
            "ochladit silnice exkurze zrnitost jiskra zprudka pstruh tlukot vytasit valoun najisto kralovat bobek uklidnit helma ubytovna pysk andulka",
        ),
        (
            .czech,
            "bavlna mozaika ofsajd kukla obliba kormidlo monarcha batoh chmura mdloba makovice obilnice popel pohnutka duchovno panika neuron okupant rukavice kouzlo stehno badatel sklenice rozchod",
        ),
        (.czech, "zajet nutrie beton kobyla kriket sranda elektron abeceda uboze lump vzorek potvora"),
        (
            .czech,
            "slezina navzdory odjinud oklika ucho ropucha rohovka zavalit graf panenka invalida katedra odebrat deska metoda ohryzek graf flotila",
        ),
        (
            .czech,
            "zavalit genetika kapusta tvrdost dopad ujmout zdobit mistr splav ptactvo fosfor hoch pocit beztak slon poplach mazivo tancovat pravda uvalit konkurs surovina nazvat vypadat",
        ),
        (.czech, "obezita pukrle adresa klec klima snad hustota pukavec obvod libra odveta dotek vila zkratka jogurt"),
        (
            .czech,
            "halenka samec majetek rozeznat hygiena koza maskot kadidlo cirkus letec stupnice bodlina krabice hydrant zabydlet vytasit zanechat schovat epos hradba blatouch",
        ),
        (.portuguese, "abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abater"),
        (.portuguese, "imitador vinheta sogro xerife veleiro pomar volumoso tratador imitador vinheta sogro xingar"),
        (
            .portuguese,
            "inalador acirrar barulho abotoar afivelar coruja abutre amostra inalador acirrar barulho abduzir",
        ),
        (.portuguese, "zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido xeque"),
        (
            .portuguese,
            "abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate acumular",
        ),
        (
            .portuguese,
            "imitador vinheta sogro xerife veleiro pomar volumoso tratador imitador vinheta sogro xerife veleiro pomar volumoso tratador imitador viga",
        ),
        (
            .portuguese,
            "inalador acirrar barulho abotoar afivelar coruja abutre amostra inalador acirrar barulho abotoar afivelar coruja abutre amostra inalador afastar",
        ),
        (
            .portuguese,
            "zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido viaduto",
        ),
        (
            .portuguese,
            "abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate alinhar",
        ),
        (
            .portuguese,
            "imitador vinheta sogro xerife veleiro pomar volumoso tratador imitador vinheta sogro xerife veleiro pomar volumoso tratador imitador vinheta sogro xerife veleiro pomar volumoso sucata",
        ),
        (
            .portuguese,
            "inalador acirrar barulho abotoar afivelar coruja abutre amostra inalador acirrar barulho abotoar afivelar coruja abutre amostra inalador acirrar barulho abotoar afivelar coruja abutre asilado",
        ),
        (
            .portuguese,
            "zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido zumbido validade",
        ),
        (.portuguese, "mexicano crosta farpa empolgar chatice fartura olaria sogro centeio defesa dedal multar"),
        (
            .portuguese,
            "fazenda invasor magreza repolho separado emenda enchente amassar valente enxerto cachorro roteiro eliminar marinho deboche rodovia locutor envolver",
        ),
        (
            .portuguese,
            "filho comentar obrigado cunhado biologia clone obrigado julgador rebolar sufixo pacote atingir filtrar edital fardado siri janta conhecer inibido vogal quiosque genoma clone impor",
        ),
        (.portuguese, "pote ringue muda benzer andaime levitar comando guloso carreira micro grilo atracar"),
        (
            .portuguese,
            "frieza sirene hibernar setembro rigidez retalho exagero cabana oliveira refugiar recrutar vazar ramal lousa segmento tocha carpete autoria",
        ),
        (
            .portuguese,
            "mimado drible baioneta fantoche bastante redonda ligeiro simpatia lamber copeiro reitor mensagem adeus resumir lombo enraizar combinar inapto fosco orfanato gincana cubano exibir global",
        ),
        (.portuguese, "bifocal semanal enlatar debulhar roedor adquirir branco resumir tora modular patrono tangente"),
        (
            .portuguese,
            "indeciso pires braveza vontade criada vogal nutrir rodeio toxina soletrar gelo elaborar ajudar sediado carpete sarjeta oficina abreviar",
        ),
        (
            .portuguese,
            "adjetivo fugir irritado engenho iluminar dourado fralda aditivo aprovar ferrugem fardado ignorado moeda mesada bisneto linda guache jejum pastel ecologia rapel acionado pneu palmada",
        ),
        (.portuguese, "turbo hoje aeronave diagrama embargo rachar bochecha abaixo sanidade extinto tridente mundial"),
        (
            .portuguese,
            "povoar gorjeta injetar janta saturar paciente ovelha vaidoso cancelar limpador confuso degelo inflamar avisar ficheiro italiano cancelar cacique",
        ),
        (
            .portuguese,
            "vaidoso calota decote sambar batida seda vazio flora queda nuvem cadeado certeiro matinal afetivo praxe moinho feno resgatar nervoso sintonia dobrador recrutar gorro tonel",
        ),
        (
            .portuguese,
            "argola atadura banquete expulsar raspador ervilha entulho combinar tutelar semanal cerveja hipnose servo oriundo urso",
        ),
        (
            .portuguese,
            "prato grelhar penca cebola afrontar tarja sanar matagal sedento arraial ativo macete terno rota olhar apertada drogaria trevo altitude manivela belga",
        ),
    ]

    /// Phrases where every word is in the wordlist, but the checksum is invalid.
    static let bip39InvalidChecksum: [(BIP39Language, String)] = [
        (
            .english,
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent abandon abandon abandon abandon abandon",
        ),
        (
            .japanese,
            "あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あらいぐま　あいこくしん　あいこくしん　あいこくしん　あいこくしん　あいこくしん",
        ),
        (.korean, "가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 가격 강도 가격 가격 가격 가격 가격"),
        (
            .spanish,
            "ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco ábaco afición ábaco ábaco ábaco ábaco ábaco",
        ),
        (.chineseSimplified, "的 的 的 的 的 的 的 的 的 的 的 的 动 的 的 的 的 的"),
        (.chineseTraditional, "的 的 的 的 的 的 的 的 的 的 的 的 動 的 的 的 的 的"),
        (
            .french,
            "abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser abaisser adéquat abaisser abaisser abaisser abaisser abaisser",
        ),
        (
            .italian,
            "abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco abaco agitare abaco abaco abaco abaco abaco",
        ),
        (
            .czech,
            "abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace abdikace balonek abdikace abdikace abdikace abdikace abdikace",
        ),
        (
            .portuguese,
            "abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate abacate acumular abacate abacate abacate abacate abacate",
        ),
    ]

    /// Individually valid SLIP-39 shares, and whether they are extendable.
    static let slip39Valid: [(Bool, String)] = [
        (
            false,
            "duckling enlarge academic academic agency result length solution fridge kidney coal piece deal husband erode duke ajar critical decision keyboard",
        ),
        (
            false,
            "shadow pistol academic always adequate wildlife fancy gross oasis cylinder mustang wrist rescue view short owner flip making coding armed",
        ),
        (
            false,
            "shadow pistol academic acid actress prayer class unknown daughter sweater depict flip twice unkind craft early superior advocate guest smoking",
        ),
        (
            false,
            "adequate smoking academic acid debut wine petition glen cluster slow rhyme slow simple epidemic rumor junk tracks treat olympic tolerate",
        ),
        (
            false,
            "adequate stay academic agency agency formal party ting frequent learn upstairs remember smear leaf damage anatomy ladle market hush corner",
        ),
        (
            false,
            "peasant leaves academic acid desert exact olympic math alive axle trial tackle drug deny decent smear dominant desert bucket remind",
        ),
        (
            false,
            "peasant leader academic agency cultural blessing percent network envelope medal junk primary human pumps jacket fragment payroll ticket evoke voice",
        ),
        (
            false,
            "liberty category beard echo animal fawn temple briefing math username various wolf aviation fancy visual holy thunder yelp helpful payment",
        ),
        (
            false,
            "liberty category beard email beyond should fancy romp founder easel pink holy hairy romp loyalty material victim owner toxic custody",
        ),
        (
            false,
            "liberty category academic easy being hazard crush diminish oral lizard reaction cluster force dilemma deploy force club veteran expect photo",
        ),
        (
            false,
            "average senior academic leaf broken teacher expect surface hour capture obesity desire negative dynamic dominant pistol mineral mailman iris aide",
        ),
        (
            false,
            "average senior academic agency curious pants blimp spew clothes slice script dress wrap firm shaft regular slavery negative theater roster",
        ),
        (
            false,
            "device stay academic always dive coal antenna adult black exceed stadium herald advance soldier busy dryer daughter evaluate minister laser",
        ),
        (
            false,
            "device stay academic always dwarf afraid robin gravity crunch adjust soul branch walnut coastal dream costume scholar mortgage mountain pumps",
        ),
        (
            false,
            "hour painting academic academic device formal evoke guitar random modern justice filter withdraw trouble identify mailman insect general cover oven",
        ),
        (
            false,
            "hour painting academic agency artist again daisy capital beaver fiber much enjoy suitable symbolic identify photo editor romp float echo",
        ),
        (
            false,
            "guilt walnut academic acid deliver remove equip listen vampire tactics nylon rhythm failure husband fatigue alive blind enemy teaspoon rebound",
        ),
        (
            false,
            "guilt walnut academic agency brave hamster hobo declare herd taste alpha slim criminal mild arcade formal romp branch pink ambition",
        ),
        (
            false,
            "eraser senior beard romp adorn nuclear spill corner cradle style ancient family general leader ambition exchange unusual garlic promise voice",
        ),
        (
            false,
            "eraser senior decision scared cargo theory device idea deliver modify curly include pancake both news skin realize vitamins away join",
        ),
        (
            false,
            "eraser senior decision roster beard treat identify grumpy salt index fake aviation theater cubic bike cause research dragon emphasis counter",
        ),
        (
            false,
            "eraser senior decision shadow artist work morning estate greatest pipeline plan ting petition forget hormone flexible general goat admit surface",
        ),
        (
            false,
            "eraser senior ceramic snake clay various huge numb argue hesitate auction category timber browser greatest hanger petition script leaf pickup",
        ),
        (
            false,
            "eraser senior ceramic shaft dynamic become junior wrist silver peasant force math alto coal amazing segment yelp velvet image paces",
        ),
        (
            false,
            "eraser senior ceramic round column hawk trust auction smug shame alive greatest sheriff living perfect corner chest sled fumes adequate",
        ),
        (
            false,
            "eraser senior decision smug corner ruin rescue cubic angel tackle skin skunk program roster trash rumor slush angel flea amazing",
        ),
        (
            false,
            "eraser senior acrobat romp bishop medical gesture pumps secret alive ultimate quarter priest subject class dictate spew material endless market",
        ),
        (
            false,
            "theory painting academic academic armed sweater year military elder discuss acne wildlife boring employer fused large satoshi bundle carbon diagnose anatomy hamster leaves tracks paces beyond phantom capital marvel lips brave detect luck",
        ),
        (
            false,
            "humidity disease academic always aluminum jewelry energy woman receiver strategy amuse duckling lying evidence network walnut tactics forget hairy rebound impulse brother survive clothes stadium mailman rival ocean reward venture always armed unwrap",
        ),
        (
            false,
            "humidity disease academic agency actress jacket gross physics cylinder solution fake mortgage benefit public busy prepare sharp friar change work slow purchase ruler again tricycle involve viral wireless mixture anatomy desert cargo upgrade",
        ),
        (
            false,
            "smear husband academic acid deadline scene venture distance dive overall parking bracelet elevator justice echo burning oven chest duke nylon",
        ),
        (
            false,
            "smear isolate academic agency alpha mandate decorate burden recover guard exercise fatal force syndrome fumes thank guest drift dramatic mule",
        ),
        (
            false,
            "finger trash academic acid average priority dish revenue academic hospital spirit western ocean fact calcium syndrome greatest plan losing dictate",
        ),
        (
            false,
            "finger traffic academic agency building lilac deny paces subject threaten diploma eclipse window unknown health slim piece dragon focus smirk",
        ),
        (
            false,
            "flavor pink beard echo depart forbid retreat become frost helpful juice unwrap reunion credit math burning spine black capital lair",
        ),
        (
            false,
            "flavor pink beard email diet teaspoon freshman identify document rebound cricket prune headset loyalty smell emission skin often square rebound",
        ),
        (
            false,
            "flavor pink academic easy credit cage raisin crazy closet lobe mobile become drink human tactics valuable hand capture sympathy finger",
        ),
        (
            false,
            "column flea academic leaf debut extra surface slow timber husky lawsuit game behavior husky swimming already paper episode tricycle scroll",
        ),
        (
            false,
            "column flea academic agency blessing garbage party software stadium verify silent umbrella therapy decorate chemical erode dramatic eclipse replace apart",
        ),
        (
            false,
            "fishing recover academic always device craft trend snapshot gums skin downtown watch device sniff hour clock public maximum garlic born",
        ),
        (
            false,
            "fishing recover academic always aircraft view software cradle fangs amazing package plastic evaluate intend penalty epidemic anatomy quarter cage apart",
        ),
        (
            false,
            "evoke garden academic academic answer wolf scandal modern warmth station devote emerald market physics surface formal amazing aquatic gesture medical",
        ),
        (
            false,
            "evoke garden academic agency deal revenue knit reunion decrease magazine flexible company goat repair alarm military facility clogs aide mandate",
        ),
        (
            false,
            "river deal academic acid average forbid pistol peanut custody bike class aunt hairy merit valid flexible learn ajar very easel",
        ),
        (
            false,
            "river deal academic agency camera amuse lungs numb isolate display smear piece traffic worthy year patrol crush fact fancy emission",
        ),
        (
            false,
            "wildlife deal beard romp alcohol space mild usual clothes union nuclear testify course research heat listen task location thank hospital slice smell failure fawn helpful priest ambition average recover lecture process dough stadium",
        ),
        (
            false,
            "wildlife deal decision scared acne fatal snake paces obtain election dryer dominant romp tactics railroad marvel trust helpful flip peanut theory theater photo luck install entrance taxi step oven network dictate intimate listen",
        ),
        (
            false,
            "wildlife deal decision smug ancestor genuine move huge cubic strategy smell game costume extend swimming false desire fake traffic vegan senior twice timber submit leader payroll fraction apart exact forward pulse tidy install",
        ),
        (
            false,
            "wildlife deal decision shadow analysis adjust bulb skunk muscle mandate obesity total guitar coal gravity carve slim jacket ruin rebuild ancestor numerous hour mortgage require herd maiden public ceiling pecan pickup shadow club",
        ),
        (
            false,
            "wildlife deal ceramic round aluminum pitch goat racism employer miracle percent math decision episode dramatic editor lily prospect program scene rebuild display sympathy have single mustang junction relate often chemical society wits estate",
        ),
        (
            false,
            "wildlife deal ceramic scatter argue equip vampire together ruin reject literary rival distance aquatic agency teammate rebound false argue miracle stay again blessing peaceful unknown cover beard acid island language debris industry idle",
        ),
        (
            false,
            "wildlife deal ceramic snake agree voter main lecture axis kitchen physics arcade velvet spine idea scroll promise platform firm sharp patrol divorce ancestor fantasy forbid goat ajar believe swimming cowboy symbolic plastic spelling",
        ),
        (
            false,
            "wildlife deal acrobat romp anxiety axis starting require metric flexible geology game drove editor edge screw helpful have huge holy making pitch unknown carve holiday numb glasses survive already tenant adapt goat fangs",
        ),
        (
            false,
            "herald flea academic cage avoid space trend estate dryer hairy evoke eyebrow improve airline artwork garlic premium duration prevent oven",
        ),
        (
            false,
            "herald flea academic client blue skunk class goat luxury deny presence impulse graduate clay join blanket bulge survive dish necklace",
        ),
        (
            false,
            "herald flea academic acne advance fused brother frozen broken game ranked ajar already believe check install theory angry exercise adult",
        ),
        (
            true,
            "testify swimming academic academic column loyalty smear include exotic bedroom exotic wrist lobe cover grief golden smart junior estimate learn",
        ),
        (
            true,
            "enemy favorite academic acid cowboy phrase havoc level response walnut budget painting inside trash adjust froth kitchen learn tidy punish",
        ),
        (
            true,
            "enemy favorite academic always academic sniff script carpet romp kind promise scatter center unfair training emphasis evening belong fake enforce",
        ),
        (
            true,
            "impulse calcium academic academic alcohol sugar lyrics pajamas column facility finance tension extend space birthday rainbow swimming purple syndrome facility trial warn duration snapshot shadow hormone rhyme public spine counter easy hawk album",
        ),
        (
            true,
            "western apart academic always artist resident briefing sugar woman oven coding club ajar merit pecan answer prisoner artist fraction amount desktop mild false necklace muscle photo wealthy alpha category unwrap spew losing making",
        ),
        (
            true,
            "western apart academic acid answer ancient auction flip image penalty oasis beaver multiple thunder problem switch alive heat inherit superior teaspoon explain blanket pencil numb lend punish endless aunt garlic humidity kidney observe",
        ),
    ]

    static let slip39InvalidChecksum: [String] = [
        "duckling enlarge academic academic agency result length solution fridge kidney coal piece deal husband erode duke ajar critical decision kidney",
        "theory painting academic academic armed sweater year military elder discuss acne wildlife boring employer fused large satoshi bundle carbon diagnose anatomy hamster leaves tracks paces beyond phantom capital marvel lips brave detect lunar",
    ]

    /// Shares with a valid checksum, but invalid padding or a group threshold greater than the group count.
    static let slip39InvalidShare: [String] = [
        "duckling enlarge academic academic email result length solution fridge kidney coal piece deal husband erode duke ajar music cargo fitness",
        "music husband acrobat acid artist finance center either graduate swimming object bike medical clothes station aspect spider maiden bulb welcome",
        "music husband acrobat agency advance hunting bike corner density careful material civil evil tactics remind hawk discuss hobo voice rainbow",
        "music husband beard academic black tricycle clock mayor estimate level photo episode exclude ecology papa source amazing salt verify divorce",
        "theory painting academic academic campus sweater year military elder discuss acne wildlife boring employer fused large satoshi bundle carbon diagnose anatomy hamster leaves tracks paces beyond phantom capital marvel lips facility obtain sister",
        "smirk pink acrobat acid auction wireless impulse spine sprinkle fortune clogs elbow guest hush loyalty crush dictate tracks airport talent",
        "smirk pink acrobat agency dwarf emperor ajar organize legs slice harvest plastic dynamic style mobile float bulb health coding credit",
        "smirk pink beard academic alto strategy carve shame language rapids ruin smart location spray training acquire eraser endorse submit peaceful",
    ]

    static let electrumValid: [(ElectrumSeedType, String)] = [
        (.segwit, "wild father tree among universe such mobile favorite target dynamic credit identify"),
        (.standard, "なのか ひろい しなん まなぶ つぶす さがす おしゃれ かわく おいかける けさき かいとう さたん"),
        (.segwit, "眼 悲 叛 改 节 跃 衡 响 疆 股 遂 冬"),
        (.standard, "almíbar tibio superar vencer hacha peatón príncipe matar consejo polen vehículo odisea"),
        (.segwit, "equipo fiar auge langosta hacha calor trance cubrir carro pulmón oro áspero"),
        (.segwit, "vidrio jabón muestra pájaro capucha eludir feliz rotar fogata pez rezar oír"),
        (.standard, "cram swing cover prefer miss modify ritual silly deliver chunk behind inform able"),
        (.standard, "ostrich security deer aunt climb inner alpha arm mutual marble solid task"),
        (.standard, "OSTRICH SECURITY DEER AUNT CLIMB INNER ALPHA ARM MUTUAL MARBLE SOLID TASK"),
        (.twoFactor, "science dawn member doll dutch real can brick knife deny drive list"),
        (
            .twoFactor,
            "bind clever room kidney crucial sausage spy edit canvas soul liquid ribbon slam open alpha suffer gate relax voice carpet law hill woman tonight abstract",
        ),
        (
            .twoFactor,
            "sibling leg cable timber patient foot occur plate travel finger chef scale radio citizen promote immune must chef fluid sea sphere common acid lab",
        ),
        (.segwit, "frost pig brisk excite novel report camera enlist axis nation novel desert"),
    ]

    /// Every word is in the wordlist, but the phrase has no valid seed version.
    static let electrumInvalid: [String] = [
        "cram swing cover prefer miss modify ritual silly deliver chunk behind inform",
        "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
    ]

    static let moneroValid: [String] = [
        "velvet lymph giddy number token physics poetry unquoted nibs useful sabotage limits benches lifestyle eden nitrogen anvil fewest avoid batch vials washing fences goat unquoted",
        "peeled mixture ionic radar utopia puddle buying illness nuns gadget river spout cavernous bounced paradise drunk looking cottage jump tequila melting went winter adjust spout",
        "dilute gutter certain antics pamphlet macro enjoy left slid guarded bogeys upload nineteen bomb jubilee enhanced irritate turnip eggs swung jukebox loudly reduce sedan slid",
    ]
}
