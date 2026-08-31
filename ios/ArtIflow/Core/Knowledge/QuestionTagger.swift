import Foundation

// MARK: - Topic rules (StudyChatModels.kt topicRules / knowledgeRules)

struct TopicRule {
    let topic: String
    let keywords: [String]
}

struct KnowledgeRule {
    let point: String
    let keywords: [String]
}

let topicRules: [TopicRule] = [
    TopicRule(topic: "函数", keywords: ["函数", "顶点", "最值", "导数", "单调"]),
    TopicRule(topic: "几何", keywords: ["几何", "三角形", "圆", "向量", "角度"]),
    TopicRule(topic: "概率", keywords: ["概率", "随机", "独立", "期望", "方差"]),
    TopicRule(topic: "物理", keywords: ["力", "加速度", "电场", "磁场", "电流"]),
    TopicRule(topic: "化学", keywords: ["氧化", "还原", "反应", "离子", "平衡"])
]

let modelKnowledgeRules: [KnowledgeRule] = [
    KnowledgeRule(point: "函数与图像", keywords: ["函数", "图像", "抛物线", "导数", "单调", "最值"]),
    KnowledgeRule(point: "方程与不等式", keywords: ["方程", "不等式", "根", "判别式", "配方", "二次"]),
    KnowledgeRule(point: "几何证明", keywords: ["几何", "三角形", "圆", "向量", "相似", "全等"]),
    KnowledgeRule(point: "概率统计", keywords: ["概率", "随机", "期望", "方差", "排列", "组合"]),
    KnowledgeRule(point: "力学", keywords: ["受力", "牛顿", "加速度", "速度", "位移", "动量"]),
    KnowledgeRule(point: "电磁学", keywords: ["电场", "电势", "电流", "电阻", "磁场", "感应"]),
    KnowledgeRule(point: "化学反应", keywords: ["氧化", "还原", "离子", "平衡", "反应", "浓度"])
]

let supportedKnowledgeSubjects: Set<String> = ["数学", "物理", "化学", "英语", "语文"]

let canonicalHighSchoolKnowledgePoints: Set<String> = {
    var set = Set(modelKnowledgeRules.map { $0.point })
    let extras = [
        "二次函数", "解析几何", "数列", "导数与应用", "三角函数",
        "运动学", "光学", "热学", "机械能",
        "有机化学", "电化学", "离子反应", "化学平衡",
        "时态与语态", "从句", "虚拟语气", "完形填空", "阅读理解",
        "文言文", "现代文阅读", "诗词鉴赏", "作文", "修辞手法"
    ]
    set.formUnion(extras)
    return set
}()

// MARK: - QuestionTagger (data/QuestionTagger.kt)

struct SubjectRule {
    let subject: String
    let keywords: [String]
}

struct TypeRule {
    let type: String
    let keywords: [String]
}

enum QuestionTagger {
    static let subjectRules: [SubjectRule] = [
        SubjectRule(subject: "数学", keywords: [
            "函数", "导数", "积分", "极限", "连续", "单调", "极值", "最值", "顶点",
            "抛物线", "图像", "值域", "定义域",
            "方程", "不等式", "根", "判别式", "配方", "二次", "因式分解",
            "几何", "三角形", "圆", "椭圆", "双曲线", "向量", "角度",
            "相似", "全等", "平行", "垂直", "距离", "面积", "体积", "周长",
            "概率", "随机", "独立", "期望", "方差", "排列", "组合", "统计", "分布", "频率",
            "数列", "等差", "等比", "通项", "求和",
            "复数", "集合", "逻辑", "命题", "充分", "必要", "充分必要"
        ]),
        SubjectRule(subject: "物理", keywords: [
            "力", "受力", "牛顿", "加速度", "速度", "位移", "动量", "冲量",
            "功", "功率", "能量", "动能", "势能", "机械能", "摩擦力", "弹力",
            "重力", "支持力", "拉力", "推力",
            "匀速", "匀加速", "自由落体", "平抛", "斜抛", "圆周运动",
            "电场", "电势", "电流", "电阻", "电压", "电容", "电感",
            "磁场", "磁感应", "安培", "洛伦兹", "感应", "电磁感应", "楞次", "法拉第",
            "光", "折射", "反射", "透镜", "凸透镜", "凹透镜", "光谱",
            "热", "温度", "热量", "内能", "熵", "理想气体", "压强",
            "声", "波", "频率", "波长", "振幅", "周期",
            "原子", "核", "衰变", "裂变", "聚变", "量子", "光电效应"
        ]),
        SubjectRule(subject: "化学", keywords: [
            "氧化", "还原", "反应", "化学方程", "离子方程", "平衡",
            "速率", "催化剂", "可逆",
            "元素", "周期表", "原子序", "电子", "质子", "中子", "主族", "副族", "周期", "族",
            "有机", "烃", "烷", "烯", "炔", "苯", "醇", "醛", "酸", "酯",
            "官能团", "同分异构", "加成", "取代", "消去",
            "无机", "金属", "非金属", "盐", "酸", "碱", "氧化物",
            "离子", "溶液", "浓度", "溶解", "电解", "电离", "pH",
            "电化学", "原电池", "电解池", "电极", "正极", "负极",
            "化学键", "共价", "离子键", "金属键", "分子间"
        ]),
        SubjectRule(subject: "英语", keywords: [
            "grammar", "时态", "语态", "从句", "定语从句", "状语从句",
            "名词性从句", "主语从句", "宾语从句", "表语从句",
            "虚拟语气", "倒装", "强调", "省略",
            "动词", "名词", "形容词", "副词", "介词", "连词", "冠词", "单复数", "不可数", "可数",
            "vocabulary", "单词", "短语", "搭配", "同义词", "反义词", "词根", "词缀", "构词",
            "reading", "comprehension", "cloze", "完形", "填空",
            "writing", "作文", "翻译", "translation", "listening", "听力"
        ]),
        SubjectRule(subject: "语文", keywords: [
            "文言", "古文", "之乎者也", "虚词", "实词", "通假", "古今异义",
            "一词多义", "词类活用", "特殊句式", "判断句", "被动句", "省略句", "倒装句",
            "现代文", "记叙", "说明", "议论", "散文", "小说", "戏剧",
            "诗词", "古诗", "词牌", "曲牌", "押韵", "对仗", "平仄", "意象", "意境", "修辞",
            "作文", "写作", "立意", "选材", "结构", "开头", "结尾", "论证", "论点", "论据",
            "比喻", "拟人", "夸张", "排比", "对偶", "反问", "设问", "借代", "通感",
            "阅读理解", "中心思想", "段落大意", "人物形象", "环境描写"
        ])
    ]

    static let knowledgeRules: [KnowledgeRule] = [
        KnowledgeRule(point: "函数与图像", keywords: ["函数", "图像", "抛物线", "导数", "单调", "最值", "极值", "顶点", "值域", "定义域"]),
        KnowledgeRule(point: "二次函数", keywords: ["二次", "抛物线", "顶点", "对称轴", "开口", "最值"]),
        KnowledgeRule(point: "方程与不等式", keywords: ["方程", "不等式", "根", "判别式", "配方", "因式分解", "解集"]),
        KnowledgeRule(point: "几何证明", keywords: ["几何", "三角形", "圆", "向量", "相似", "全等", "证明"]),
        KnowledgeRule(point: "解析几何", keywords: ["椭圆", "双曲线", "抛物线", "圆", "坐标", "方程", "离心率", "焦距"]),
        KnowledgeRule(point: "概率统计", keywords: ["概率", "随机", "期望", "方差", "排列", "组合", "分布", "频率"]),
        KnowledgeRule(point: "数列", keywords: ["数列", "等差", "等比", "通项", "求和", "递推"]),
        KnowledgeRule(point: "导数与应用", keywords: ["导数", "切线", "极值", "最值", "单调", "凹凸"]),
        KnowledgeRule(point: "三角函数", keywords: ["正弦", "余弦", "正切", "三角", "弧度", "周期"]),
        KnowledgeRule(point: "力学", keywords: ["受力", "牛顿", "加速度", "速度", "位移", "动量", "冲量", "功", "功率"]),
        KnowledgeRule(point: "运动学", keywords: ["匀速", "匀加速", "自由落体", "平抛", "斜抛", "圆周运动", "相对运动"]),
        KnowledgeRule(point: "电磁学", keywords: ["电场", "电势", "电流", "电阻", "电压", "磁场", "感应", "安培", "洛伦兹"]),
        KnowledgeRule(point: "光学", keywords: ["光", "折射", "反射", "透镜", "光谱", "干涉", "衍射"]),
        KnowledgeRule(point: "热学", keywords: ["热", "温度", "热量", "内能", "熵", "理想气体", "压强", "体积"]),
        KnowledgeRule(point: "机械能", keywords: ["动能", "势能", "机械能", "能量守恒", "动能定理"]),
        KnowledgeRule(point: "化学反应", keywords: ["氧化", "还原", "反应", "平衡", "速率", "催化剂"]),
        KnowledgeRule(point: "有机化学", keywords: ["有机", "烃", "烷", "烯", "炔", "苯", "醇", "醛", "酸", "酯", "官能团"]),
        KnowledgeRule(point: "电化学", keywords: ["电化学", "原电池", "电解池", "电极", "氧化还原"]),
        KnowledgeRule(point: "离子反应", keywords: ["离子", "电解", "电离", "离子方程", "沉淀", "气体"]),
        KnowledgeRule(point: "化学平衡", keywords: ["平衡", "可逆", "勒夏特列", "转化率", "平衡常数"]),
        KnowledgeRule(point: "时态与语态", keywords: ["时态", "语态", "被动", "进行", "完成", "将来", "过去"]),
        KnowledgeRule(point: "从句", keywords: ["从句", "定语", "状语", "主语", "宾语", "表语", "同位语"]),
        KnowledgeRule(point: "虚拟语气", keywords: ["虚拟", "条件", "wish", "if", "would", "should", "could", "might"]),
        KnowledgeRule(point: "完形填空", keywords: ["完形", "cloze", "填空", "上下文"]),
        KnowledgeRule(point: "阅读理解", keywords: ["reading", "comprehension", "理解", "主旨", "细节", "推断"]),
        KnowledgeRule(point: "文言文", keywords: ["文言", "古文", "虚词", "实词", "通假", "古今异义", "一词多义"]),
        KnowledgeRule(point: "诗词鉴赏", keywords: ["诗词", "古诗", "意象", "意境", "修辞", "手法", "情感"]),
        KnowledgeRule(point: "现代文阅读", keywords: ["现代文", "记叙", "说明", "议论", "散文", "中心思想", "人物形象"]),
        KnowledgeRule(point: "作文", keywords: ["作文", "写作", "立意", "选材", "结构", "论证", "论点", "论据"]),
        KnowledgeRule(point: "修辞手法", keywords: ["比喻", "拟人", "夸张", "排比", "对偶", "反问", "设问", "借代", "通感"])
    ]

    static let typeRules: [TypeRule] = [
        TypeRule(type: "选择题", keywords: [
            "下列", "选项", "A.", "B.", "C.", "D.", "A、", "B、", "C、", "D、",
            "正确的是", "错误的是", "不正确的是", "选择", "单选", "多选", "选出"
        ]),
        TypeRule(type: "填空题", keywords: ["填写", "填空", "____", "______", "________", "横线", "空白处", "补全", "空格"]),
        TypeRule(type: "解答题", keywords: ["解答", "证明", "计算", "求证", "求", "求解", "试求", "请证明", "请计算", "请解答"]),
        TypeRule(type: "简答题", keywords: ["简述", "简答", "说明", "分析", "简析", "简要", "概述", "归纳", "总结"]),
        TypeRule(type: "应用题", keywords: ["应用", "实际", "生活中", "某公司", "某工厂", "工程", "行程", "利润", "成本", "售价"])
    ]

    struct TagResult {
        let subject: String
        let knowledgePoints: [String]
        let questionType: String
    }

    static func autoTag(_ text: String) -> TagResult {
        return TagResult(
            subject: detectSubject(text),
            knowledgePoints: detectKnowledgePoints(text),
            questionType: detectQuestionType(text)
        )
    }

    static func detectSubject(_ text: String) -> String {
        let normalized = text.lowercased()
        let scores = subjectRules.map { rule -> (subject: String, score: Int) in
            let count = rule.keywords.filter { normalized.contains($0.lowercased()) }.count
            return (rule.subject, count)
        }
        let maxScore = scores.map { $0.score }.max() ?? 0
        if maxScore > 0 {
            return scores.first { $0.score == maxScore }!.subject
        }
        return "通用"
    }

    static func detectKnowledgePoints(_ text: String) -> [String] {
        let normalized = text.lowercased()
        let matched = knowledgeRules.compactMap { rule -> (point: String, score: Int)? in
            let count = rule.keywords.filter { normalized.contains($0.lowercased()) }.count
            return count > 0 ? (rule.point, count) : nil
        }
        return matched
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map { $0.point }
    }

    static func detectQuestionType(_ text: String) -> String {
        let normalized = text.lowercased()
        let scores = typeRules.map { rule -> (type: String, score: Int) in
            let count = rule.keywords.filter { normalized.contains($0.lowercased()) }.count
            return (rule.type, count)
        }
        let maxScore = scores.map { $0.score }.max() ?? 0
        if maxScore > 0 {
            return scores.first { $0.score == maxScore }!.type
        }
        return "其他"
    }
}

// MARK: - Topic / knowledge detection helpers (StudyChatModels.kt)

func detectTopicsForProfile(_ text: String) -> [String] {
    let normalized = text.lowercased()
    let matched = topicRules.filter { rule in
        rule.keywords.contains { normalized.contains($0) }
    }.map { $0.topic }
    return matched.isEmpty ? ["通用方法"] : matched
}

extension ProfileState {
    func updateWith(text: String, isFollowup: Bool, isVoice: Bool) -> ProfileState {
        var hits = topicHits
        for topic in detectTopicsForProfile(text) {
            hits[topic, default: 0] += 1
        }
        return ProfileState(
            level: level,
            topicHits: hits,
            followups: followups + (isFollowup ? 1 : 0),
            voiceFollowups: voiceFollowups + (isVoice ? 1 : 0)
        )
    }
}
