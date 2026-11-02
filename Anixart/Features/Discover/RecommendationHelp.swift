/// Original Anixart 10.5 APK: DiscoverFragment binds btn_recommendations_more
/// to Ll1Il1I11lI.onClick case 1. Its native information dialog uses the exact
/// resources information (0x7f1304ff), no_recommendation_info (0x7f1306ad) and
/// understand (0x7f13094d). This is help text, not an iOS-side eligibility rule.
enum RecommendationHelp {
    static let title = "Информация"
    static let dismissTitle = "Понятно"
    static let message = """
    Рекомендации подбираются автоматически на основе выставленных вами оценок.

    Для подбора вы должны положительно оценить не менее 20 релизов, однако помните: чем честнее выставлены оценки, тем точнее будут подобраны рекомендации.

    Обновление происходит раз в сутки.
    """
}
