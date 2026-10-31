import XCTest
@testable import MeetingImporterCore

final class MeetingTextParserTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    private var referenceDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 10))!
    }

    func testParsesExampleNotification() {
        let text = """
        关于召开产品周会的通知
        时间：下周五下午2点至3点30分
        地点：创意园 A3-201 会议室
        参会人员：产品部、设计部、研发负责人
        腾讯会议：https://meeting.tencent.com/example
        """

        let result = MeetingTextParser(calendar: calendar).parse(text, referenceDate: referenceDate)
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.draft.startDate)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.draft.endDate)

        XCTAssertEqual(result.draft.title, "产品周会")
        XCTAssertEqual(start, DateComponents(year: 2026, month: 7, day: 17, hour: 14, minute: 0))
        XCTAssertEqual(end, DateComponents(year: 2026, month: 7, day: 17, hour: 15, minute: 30))
        XCTAssertEqual(result.draft.location, "创意园 A3-201 会议室")
        XCTAssertEqual(result.draft.attendees, "产品部、设计部、研发负责人")
        XCTAssertEqual(result.draft.meetingURL, "https://meeting.tencent.com/example")
        XCTAssertTrue(result.draft.warnings.contains(where: { $0.contains("相对星期") }))
    }

    func testParsesManualTemplateForDirectImport() {
        let text = """
        时间：7月11日上午9点至10点
        地点：第二会议室
        参加人：办公室、财务部负责人
        会议主题：季度工作协调会
        线上会议链接：https://meeting.example.com/123
        """

        let result = MeetingTextParser(calendar: calendar).parse(text, referenceDate: referenceDate)
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.draft.startDate)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.draft.endDate)

        XCTAssertEqual(result.method, .localRules)
        XCTAssertEqual(result.draft.title, "季度工作协调会")
        XCTAssertEqual(start, DateComponents(year: 2026, month: 7, day: 11, hour: 9, minute: 0))
        XCTAssertEqual(end, DateComponents(year: 2026, month: 7, day: 11, hour: 10, minute: 0))
        XCTAssertEqual(result.draft.location, "第二会议室")
        XCTAssertEqual(result.draft.attendees, "办公室、财务部负责人")
        XCTAssertEqual(result.draft.meetingURL, "https://meeting.example.com/123")
    }

    func testExtractsLocationFromNaturalConveneSentence() {
        let draft = MeetingTextParser(calendar: calendar).parse(
            "7月20日上午在A203会议室召开会议",
            referenceDate: referenceDate
        ).draft

        XCTAssertEqual(draft.location, "A203会议室")
        XCTAssertEqual(draft.title, "会议安排")
    }

    func testExtractsLocationFromNaturalResearchSentence() {
        let draft = MeetingTextParser(calendar: calendar).parse(
            "明天下午在第一会议室研究下半年工作安排，请办公室、财务部参加。",
            referenceDate: referenceDate
        ).draft

        XCTAssertEqual(draft.location, "第一会议室")
        XCTAssertEqual(draft.attendees, "办公室、财务部")
    }

    func testParsesTemplateStartAndEndDates() {
        let text = """
        会议名称：集中评审会
        开始日期：2026年7月11日
        截止日期：2026年7月13日
        起始时间：上午9点至10点
        地点：第二会议室
        """

        let result = MeetingTextParser(calendar: calendar).parse(text, referenceDate: referenceDate)
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.draft.startDate)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.draft.endDate)

        XCTAssertEqual(result.draft.title, "集中评审会")
        XCTAssertEqual(start, DateComponents(year: 2026, month: 7, day: 11, hour: 9, minute: 0))
        XCTAssertEqual(end, DateComponents(year: 2026, month: 7, day: 13, hour: 10, minute: 0))
    }

    func testParsesInlineDateRange() {
        let draft = MeetingTextParser(calendar: calendar).parse(
            "会议名称：培训会\n日期：7月11日到13日\n时间：上午9点",
            referenceDate: referenceDate
        ).draft
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.startDate)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.endDate)

        XCTAssertEqual(start, DateComponents(year: 2026, month: 7, day: 11, hour: 9, minute: 0))
        XCTAssertEqual(end, DateComponents(year: 2026, month: 7, day: 13, hour: 9, minute: 0))
    }

    func testUsesMainMeetingContentAsTitleForDirectImport() {
        let text = """
        日期：7月12日
        时间：下午2点至3点
        地点：第一会议室
        参加人：项目组负责人
        主要会议内容：下半年重点项目协调会
        """

        let draft = MeetingTextParser(calendar: calendar).parse(text, referenceDate: referenceDate).draft

        XCTAssertEqual(draft.title, "下半年重点项目协调会")
        XCTAssertEqual(draft.location, "第一会议室")
        XCTAssertEqual(draft.attendees, "项目组负责人")
    }

    func testFormatsUnpunctuatedSpeechIntoTemplateLines() {
        let transcript = "会议名称局务会党组会日期2026年7月2日时间上午9点到10点地点总局大楼A213会议室参会人员办公室主要会议内容审议年度计划"

        let formatted = MeetingSpeechFormatter.format(transcript)

        XCTAssertEqual(formatted, """
        会议名称：局务会党组会
        日期：2026年7月2日
        起始时间：上午9点到10点
        地点：总局大楼A213会议室
        参会人员：办公室
        主要会议内容：审议年度计划
        """)
    }

    func testFormatsCompleteSpokenTemplateWithoutMixingLocationAndAttendees() {
        let transcript = "会议名称培训会起始日期7月11日结束日期7月13日起始时间上午9点到10点地点培训中心参会人员办公室主要内容集中培训"

        let formatted = MeetingSpeechFormatter.format(transcript)

        XCTAssertEqual(formatted, """
        会议名称：培训会
        开始日期：7月11日
        截止日期：7月13日
        起始时间：上午9点到10点
        地点：培训中心
        参会人员：办公室
        主要内容：集中培训
        """)
    }

    func testLocationUnitIsNotCopiedIntoAttendeesWhenAttendeesAreMissing() {
        let transcript = "会议名称餐会日期7月16日起始时间晚上6点地点宴会中心主要内容部门聚餐"
        let formatted = MeetingSpeechFormatter.format(transcript)
        let normalized = MeetingTextParser(calendar: calendar).normalizingSpokenTemplateDate(
            formatted,
            referenceDate: referenceDate
        )

        let draft = MeetingTextParser(calendar: calendar).parse(normalized, referenceDate: referenceDate).draft

        XCTAssertEqual(draft.location, "宴会中心")
        XCTAssertEqual(draft.attendees, "")
    }

    func testNormalizesSpokenRelativeDateWithWeekdayInOriginalText() {
        let transcript = MeetingSpeechFormatter.format(
            "会议名称办公会日期下周三起始时间上午9点地点教学楼A106会议室参会人员办公室主要会议内容研究工作安排"
        )

        let normalized = MeetingTextParser(calendar: calendar).normalizingSpokenTemplateDate(
            transcript,
            referenceDate: referenceDate
        )

        XCTAssertTrue(normalized.contains("开始日期：2026年7月15日（星期三）"))
        XCTAssertTrue(normalized.contains("起始时间：上午9点"))
    }

    func testNormalizesSpokenDateRangeIntoStartAndEndDates() {
        let transcript = MeetingSpeechFormatter.format(
            "会议名称培训会日期7月11日到13日起始时间上午9点主要内容集中培训"
        )

        let normalized = MeetingTextParser(calendar: calendar).normalizingSpokenTemplateDate(
            transcript,
            referenceDate: referenceDate
        )
        let draft = MeetingTextParser(calendar: calendar).parse(normalized, referenceDate: referenceDate).draft
        let start = calendar.dateComponents([.year, .month, .day], from: draft.startDate)
        let end = calendar.dateComponents([.year, .month, .day], from: draft.endDate)

        XCTAssertTrue(normalized.contains("开始日期：2026年7月11日（星期六）"))
        XCTAssertTrue(normalized.contains("截止日期：2026年7月13日（星期一）"))
        XCTAssertEqual(start, DateComponents(year: 2026, month: 7, day: 11))
        XCTAssertEqual(end, DateComponents(year: 2026, month: 7, day: 13))
    }

    func testNormalizesSingleSpokenDateAsStartDateOnly() {
        let transcript = MeetingSpeechFormatter.format("会议名称办公会日期7月12日起始时间上午9点")

        let normalized = MeetingTextParser(calendar: calendar).normalizingSpokenTemplateDate(
            transcript,
            referenceDate: referenceDate
        )
        let draft = MeetingTextParser(calendar: calendar).parse(normalized, referenceDate: referenceDate).draft

        XCTAssertTrue(normalized.contains("开始日期：2026年7月12日（星期日）"))
        XCTAssertFalse(normalized.contains("截止日期："))
        XCTAssertEqual(draft.endDate.timeIntervalSince(draft.startDate), 60 * 60)
    }

    func testAddsDefaultDurationWhenEndTimeIsMissing() {
        let text = """
        主题：预算评审会
        日期：2026年7月18日
        时间：上午9:20
        """

        let result = MeetingTextParser(calendar: calendar).parse(text, referenceDate: referenceDate)

        XCTAssertEqual(result.draft.endDate.timeIntervalSince(result.draft.startDate), 60 * 60)
        XCTAssertTrue(result.draft.warnings.contains(where: { $0.contains("结束时间") && $0.contains("默认一小时") }))
    }

    func testMissingTimesCreateWarnings() {
        let result = MeetingTextParser(calendar: calendar).parse("日期：7月20日", referenceDate: referenceDate)

        XCTAssertTrue(result.draft.warnings.contains(where: { $0.contains("开始时间") && $0.contains("09:00") }))
        XCTAssertTrue(result.draft.warnings.contains(where: { $0.contains("结束时间") && $0.contains("默认一小时") }))
    }

    func testAIExportRequiresConfiguredProvider() {
        XCTAssertFalse(MeetingExportAvailability.canUseAI(
            text: "日期：7月20日",
            isAnalyzing: false,
            isAIConfigured: false
        ))
        XCTAssertTrue(MeetingExportAvailability.canUseAI(
            text: "日期：7月20日",
            isAnalyzing: false,
            isAIConfigured: true
        ))
        XCTAssertTrue(MeetingExportAvailability.canUseLocalRules(
            text: "日期：7月20日",
            isAnalyzing: false
        ))
    }

    func testCalendarNotesKeepOriginalTextWithoutSummary() {
        let original = "主题：复盘会\n时间：明天下午3点"
        let draft = MeetingTextParser(calendar: calendar).parse(original, referenceDate: referenceDate).draft

        XCTAssertFalse(draft.calendarNotes.contains("会议摘要"))
        XCTAssertTrue(draft.calendarNotes.contains("会议通知原文"))
        XCTAssertTrue(draft.calendarNotes.contains(original))
    }

    func testCondensesTitleFromMainTopicWhenNoTitleIsProvided() {
        let text = """
        各位同事：
        请于7月18日下午在第一会议室开会，主要研究数字化转型实施方案及下一阶段任务。
        """

        let draft = MeetingTextParser(calendar: calendar).parse(text, referenceDate: referenceDate).draft
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.startDate)

        XCTAssertEqual(draft.title, "数字化转型实施方案及下一阶段任务研究会")
        XCTAssertEqual(start, DateComponents(year: 2026, month: 7, day: 18, hour: 14, minute: 0))
        XCTAssertEqual(draft.endDate.timeIntervalSince(draft.startDate), 60 * 60)
    }

    func testUsesCurrentYearForYearlessDateEvenWhenDateHasPassed() {
        let draft = MeetingTextParser(calendar: calendar).parse("1月5日上午讨论年度计划", referenceDate: referenceDate).draft
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.startDate)

        XCTAssertEqual(components, DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 0))
    }

    func testParsesNextMonthDayAsConcreteDate() {
        let draft = MeetingTextParser(calendar: calendar).parse("下个月5号上午召开办公会", referenceDate: referenceDate).draft
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.startDate)

        XCTAssertEqual(components, DateComponents(year: 2026, month: 8, day: 5, hour: 9, minute: 0))
        XCTAssertTrue(draft.warnings.contains(where: { $0.contains("下个月5号") }))
    }

    func testBareNextWeekDefaultsToNextMondayWithWarning() {
        let draft = MeetingTextParser(calendar: calendar).parse("下周上午召开办公会", referenceDate: referenceDate).draft
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.startDate)

        XCTAssertEqual(components, DateComponents(year: 2026, month: 7, day: 13, hour: 9, minute: 0))
        XCTAssertTrue(draft.warnings.contains(where: { $0.contains("下周一") }))
    }

    func testBareNextMonthDefaultsToFirstDayWithWarning() {
        let draft = MeetingTextParser(calendar: calendar).parse("下个月下午召开办公会", referenceDate: referenceDate).draft
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.startDate)

        XCTAssertEqual(components, DateComponents(year: 2026, month: 8, day: 1, hour: 14, minute: 0))
        XCTAssertTrue(draft.warnings.contains(where: { $0.contains("下月1日") }))
    }

    func testEveningWithoutExactTimeDefaultsTo1830() {
        let draft = MeetingTextParser(calendar: calendar).parse("明天晚上研究发布方案", referenceDate: referenceDate).draft
        let components = calendar.dateComponents([.hour, .minute], from: draft.startDate)

        XCTAssertEqual(components, DateComponents(hour: 18, minute: 30))
    }

    func testExtractsAttendeesFromInvitationSentence() {
        let text = """
        明天下午研究新版本发布计划。
        请产品部、设计中心和研发项目组负责人参加。
        """

        let draft = MeetingTextParser(calendar: calendar).parse(text, referenceDate: referenceDate).draft

        XCTAssertEqual(draft.attendees, "产品部、设计中心和研发项目组负责人")
    }

    func testFallsBackToUnitsMentionedInBody() {
        let text = "明天上午讨论预算安排，财务部、采购中心共同研究后续工作。"

        let draft = MeetingTextParser(calendar: calendar).parse(text, referenceDate: referenceDate).draft

        XCTAssertTrue(draft.attendees.contains("财务部"))
        XCTAssertTrue(draft.attendees.contains("采购中心"))
    }

    func testMapsZhipuJSONAndAppliesDefaultDuration() {
        let notice = "【周四上午局务会党组会通知】定于7月2日上午9点在总局大楼A213会议室召开局务会、党组会。"
        let payload = AIMeetingPayload(
            title: "局务会、党组会",
            date: "2026-07-02",
            startTime: "09:00",
            endTime: nil,
            location: "总局大楼A213会议室",
            meetingURL: "",
            attendees: "总工、机关各部门主要负责同志",
            warnings: []
        )

        let result = MeetingAIResultMapper().map(
            payload,
            originalText: notice,
            referenceDate: referenceDate,
            method: .zhipuAI
        )
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.draft.startDate)

        XCTAssertEqual(result.method, .zhipuAI)
        XCTAssertEqual(result.draft.title, "局务会、党组会")
        XCTAssertEqual(result.draft.location, "总局大楼A213会议室")
        XCTAssertEqual(start, DateComponents(year: 2026, month: 7, day: 2, hour: 9, minute: 0))
        XCTAssertEqual(result.draft.endDate.timeIntervalSince(result.draft.startDate), 60 * 60)
    }

    func testMapsAIStartAndEndDates() {
        let payload = AIMeetingPayload(
            title: "集中培训会",
            startDate: "2026-07-11",
            endDate: "2026-07-13",
            startTime: "09:00",
            endTime: "17:30",
            location: "培训中心",
            meetingURL: "",
            attendees: "",
            warnings: []
        )

        let result = MeetingAIResultMapper().map(
            payload,
            originalText: "7月11日至13日集中培训",
            referenceDate: referenceDate,
            method: .zhipuAI
        )
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.draft.startDate)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result.draft.endDate)

        XCTAssertEqual(start, DateComponents(year: 2026, month: 7, day: 11, hour: 9, minute: 0))
        XCTAssertEqual(end, DateComponents(year: 2026, month: 7, day: 13, hour: 17, minute: 30))
    }

    func testSharedMapperMarksOpenRouterBackupResult() {
        let payload = AIMeetingPayload(
            title: "党组会",
            date: "2026-07-02",
            startTime: "09:00",
            endTime: "10:00",
            location: "A213会议室",
            meetingURL: nil,
            attendees: nil,
            warnings: []
        )

        let result = MeetingAIResultMapper().map(
            payload,
            originalText: "7月2日上午9点召开党组会",
            referenceDate: referenceDate,
            method: .openRouterAI
        )

        XCTAssertEqual(result.method, .openRouterAI)
        XCTAssertEqual(result.draft.title, "党组会")
    }
}
