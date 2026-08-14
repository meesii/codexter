class SummaryNotice {
    final String workspaceUuid;
    final String workspaceName;
    final String title;
    final String summary;
    final List<String> details;
    final DateTime endedAt;

    const SummaryNotice({
        required this.workspaceUuid,
        required this.workspaceName,
        required this.title,
        required this.summary,
        required this.details,
        required this.endedAt,
    });
}

typedef SummaryHandler = void Function(SummaryNotice notice);
