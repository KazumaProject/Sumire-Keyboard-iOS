import Combine
import SwiftUI

@MainActor
final class DictionaryManagementViewModel: ObservableObject {
    let repositories: DictionaryRepositories?
    @Published var errorMessage: String?

    init() {
        do {
            repositories = try DictionaryRepositoryContainer.makeDefault()
        } catch {
            repositories = nil
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class LearningDictionaryManagementViewModel: ObservableObject {
    @Published var entries: [LearningDictionaryEntry] = []
    @Published var query = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let queryRepository: any LearningDictionaryQueryRepository
    private let editorRepository: any LearningDictionaryEditorRepository

    init(
        queryRepository: any LearningDictionaryQueryRepository,
        editorRepository: any LearningDictionaryEditorRepository
    ) {
        self.queryRepository = queryRepository
        self.editorRepository = editorRepository
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            entries = try await queryRepository.searchForManagementUI(
                query: query,
                limit: 200,
                offset: 0
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ draft: DictionaryEntryDraft, editing entry: LearningDictionaryEntry?) async {
        do {
            let now = Date()
            let nextEntry = LearningDictionaryEntry(
                id: entry?.id ?? UUID(),
                reading: draft.reading,
                word: draft.word,
                score: draft.score,
                leftId: draft.leftId,
                rightId: draft.rightId,
                updatedAt: now
            )
            if entry == nil {
                try await editorRepository.add(nextEntry)
            } else {
                try await editorRepository.update(nextEntry)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ entry: LearningDictionaryEntry) async {
        do {
            try await editorRepository.delete(id: entry.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAll() async {
        do {
            try await editorRepository.deleteAll()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class UserDictionaryManagementViewModel: ObservableObject {
    @Published var entries: [UserDictionaryEntry] = []
    @Published var query = ""
    @Published var isLoading = false
    @Published var buildState = UserDictionaryBuildState(status: .idle, updatedAt: Date())
    @Published var successMessage: String?
    @Published var errorMessage: String?

    private let queryRepository: any UserDictionaryManagementQueryRepository
    private let editorRepository: any UserDictionaryEditorRepository
    private let loudsBuilder: any UserDictionaryLoudsBuilder
    private let loudsValidator: any UserDictionaryLoudsValidator
    private let artifactPublisher: any UserDictionaryArtifactPublisher
    private let buildStateRepository: any UserDictionaryBuildStateRepository

    var isBuilding: Bool {
        switch buildState.status {
        case .building, .validating:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    init(
        queryRepository: any UserDictionaryManagementQueryRepository,
        editorRepository: any UserDictionaryEditorRepository,
        loudsBuilder: any UserDictionaryLoudsBuilder = FileUserDictionaryLoudsBuilder(),
        loudsValidator: any UserDictionaryLoudsValidator = FileUserDictionaryLoudsValidator(),
        artifactPublisher: any UserDictionaryArtifactPublisher = FileUserDictionaryArtifactPublisher(),
        buildStateRepository: any UserDictionaryBuildStateRepository = FileUserDictionaryBuildStateRepository()
    ) {
        self.queryRepository = queryRepository
        self.editorRepository = editorRepository
        self.loudsBuilder = loudsBuilder
        self.loudsValidator = loudsValidator
        self.artifactPublisher = artifactPublisher
        self.buildStateRepository = buildStateRepository
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            entries = try await queryRepository.searchForManagementUI(
                query: query,
                limit: 200,
                offset: 0
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ draft: DictionaryEntryDraft, editing entry: UserDictionaryEntry?) async {
        do {
            let now = Date()
            let nextEntry = UserDictionaryEntry(
                id: entry?.id ?? UUID(),
                reading: draft.reading,
                word: draft.word,
                score: draft.score,
                leftId: draft.leftId,
                rightId: draft.rightId,
                updatedAt: now
            )
            if entry == nil {
                try await editorRepository.add(nextEntry)
            } else {
                try await editorRepository.update(nextEntry)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ entry: UserDictionaryEntry) async {
        do {
            try await editorRepository.delete(id: entry.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAll() async {
        do {
            try await editorRepository.deleteAll()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadBuildState() async {
        do {
            buildState = try await buildStateRepository.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func buildUserDictionary() async {
        let startedAt = Date()
        successMessage = nil
        errorMessage = nil
        buildState = UserDictionaryBuildState(status: .building, updatedAt: startedAt)

        do {
            try await buildStateRepository.save(buildState)
            let allEntries = try await queryRepository.allEntries()
            let artifacts = try await loudsBuilder.build(from: allEntries)

            buildState = UserDictionaryBuildState(status: .validating, updatedAt: Date())
            try await buildStateRepository.save(buildState)
            try await loudsValidator.validate(artifacts)
            try await artifactPublisher.publish(artifacts)

            let readyState = UserDictionaryBuildState(
                status: .ready,
                updatedAt: Date(),
                artifactVersion: artifacts.directoryURL.lastPathComponent
            )
            buildState = readyState
            try await buildStateRepository.save(readyState)
            successMessage = "LOUDS のビルドが完了しました。"
            await load()
        } catch {
            let message = error.localizedDescription
            let failedState = UserDictionaryBuildState(
                status: .failed(message),
                updatedAt: Date(),
                artifactVersion: buildState.artifactVersion,
                lastErrorMessage: message
            )
            buildState = failedState
            try? await buildStateRepository.save(failedState)
            errorMessage = message
        }
    }
}

struct DictionaryManagementView: View {
    @StateObject private var viewModel = DictionaryManagementViewModel()

    var body: some View {
        Form {
            if let errorMessage = viewModel.errorMessage {
                Section("エラー") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("辞書") {
                if let repositories = viewModel.repositories {
                    NavigationLink {
                        LearningDictionaryManagementView(
                            viewModel: LearningDictionaryManagementViewModel(
                                queryRepository: repositories.learningRepository,
                                editorRepository: repositories.learningRepository
                            )
                        )
                    } label: {
                        Label("学習辞書", systemImage: "clock.arrow.circlepath")
                    }

                    NavigationLink {
                        UserDictionaryManagementView(
                            viewModel: UserDictionaryManagementViewModel(
                                queryRepository: repositories.userRepository,
                                editorRepository: repositories.userRepository
                            )
                        )
                    } label: {
                        Label("ユーザー辞書", systemImage: "person.text.rectangle")
                    }
                } else {
                    Text("辞書データベースを開けませんでした。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("辞書管理")
    }
}

struct LearningDictionaryManagementView: View {
    @StateObject var viewModel: LearningDictionaryManagementViewModel
    @State private var editorRoute: LearningEditorRoute?
    @State private var showsDeleteAllConfirmation = false

    init(viewModel: LearningDictionaryManagementViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            ForEach(viewModel.entries) { entry in
                DictionaryEntryRow(
                    reading: entry.reading,
                    word: entry.word,
                    score: entry.score,
                    leftId: entry.leftId,
                    rightId: entry.rightId,
                    updatedAt: entry.updatedAt
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    editorRoute = .edit(entry)
                }
                .swipeActions {
                    Button("削除", role: .destructive) {
                        Task {
                            await viewModel.delete(entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("学習辞書")
        .searchable(text: $viewModel.query, prompt: "読み・単語で検索")
        .onSubmit(of: .search) {
            Task {
                await viewModel.load()
            }
        }
        .onChange(of: viewModel.query) {
            Task {
                await viewModel.load()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("全削除", role: .destructive) {
                    showsDeleteAllConfirmation = true
                }
                .disabled(viewModel.entries.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorRoute = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("学習辞書を追加")
            }
        }
        .confirmationDialog("学習辞書をすべて削除しますか", isPresented: $showsDeleteAllConfirmation) {
            Button("全削除", role: .destructive) {
                Task {
                    await viewModel.deleteAll()
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            DictionaryEntryEditorView(
                title: route.title,
                initialDraft: route.draft
            ) { draft in
                Task {
                    await viewModel.save(draft, editing: route.entry)
                    editorRoute = nil
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

struct UserDictionaryManagementView: View {
    @StateObject var viewModel: UserDictionaryManagementViewModel
    @State private var editorRoute: UserEditorRoute?
    @State private var showsDeleteAllConfirmation = false

    init(viewModel: UserDictionaryManagementViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            loudsBuildSection

            if viewModel.isLoading {
                ProgressView()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            ForEach(viewModel.entries) { entry in
                DictionaryEntryRow(
                    reading: entry.reading,
                    word: entry.word,
                    score: entry.score,
                    leftId: entry.leftId,
                    rightId: entry.rightId,
                    updatedAt: entry.updatedAt
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    editorRoute = .edit(entry)
                }
                .swipeActions {
                    Button("削除", role: .destructive) {
                        Task {
                            await viewModel.delete(entry)
                        }
                    }
                }
            }
        }
        .navigationTitle("ユーザー辞書")
        .searchable(text: $viewModel.query, prompt: "読み・単語で検索")
        .onSubmit(of: .search) {
            Task {
                await viewModel.load()
            }
        }
        .onChange(of: viewModel.query) {
            Task {
                await viewModel.load()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("全削除", role: .destructive) {
                    showsDeleteAllConfirmation = true
                }
                .disabled(viewModel.entries.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorRoute = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("ユーザー辞書を追加")
            }
        }
        .confirmationDialog("ユーザー辞書をすべて削除しますか", isPresented: $showsDeleteAllConfirmation) {
            Button("全削除", role: .destructive) {
                Task {
                    await viewModel.deleteAll()
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            DictionaryEntryEditorView(
                title: route.title,
                initialDraft: route.draft
            ) { draft in
                Task {
                    await viewModel.save(draft, editing: route.entry)
                    editorRoute = nil
                }
            }
        }
        .task {
            await viewModel.loadBuildState()
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var loudsBuildSection: some View {
        Section("LOUDS") {
            Button {
                Task {
                    await viewModel.buildUserDictionary()
                }
            } label: {
                Label("LOUDS をビルド", systemImage: "hammer")
            }
            .disabled(viewModel.isBuilding)

            LabeledContent("状態") {
                Text(buildStatusText)
                    .foregroundStyle(buildStatusColor)
            }

            LabeledContent("最終更新") {
                Text(viewModel.buildState.updatedAt, style: .date)
            }

            if let artifactVersion = viewModel.buildState.artifactVersion {
                LabeledContent("artifact") {
                    Text(artifactVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let successMessage = viewModel.successMessage {
                Text(successMessage)
                    .foregroundStyle(.green)
            }
        }
    }

    private var buildStatusText: String {
        switch viewModel.buildState.status {
        case .idle:
            return "idle"
        case .building:
            return "building"
        case .validating:
            return "validating"
        case .ready:
            return "ready"
        case .failed(let message):
            return "failed: \(message)"
        }
    }

    private var buildStatusColor: Color {
        switch viewModel.buildState.status {
        case .idle, .building, .validating:
            return .secondary
        case .ready:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct DictionaryEntryRow: View {
    let reading: String
    let word: String
    let score: Int
    let leftId: Int
    let rightId: Int
    let updatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(word)
                    .font(.body)
                Spacer()
                Text(reading)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("score \(score)")
                Text("L \(leftId)")
                Text("R \(rightId)")
                Spacer()
                Text(updatedAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct DictionaryEntryDraft: Hashable {
    var reading: String
    var word: String
    var score: Int
    var leftId: Int
    var rightId: Int

    var isValid: Bool {
        reading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

private struct DictionaryEntryEditorView: View {
    let title: String
    let onSave: (DictionaryEntryDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: DictionaryEntryDraft

    init(
        title: String,
        initialDraft: DictionaryEntryDraft,
        onSave: @escaping (DictionaryEntryDraft) -> Void
    ) {
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("読み", text: $draft.reading)
                    TextField("単語", text: $draft.word)
                }

                Section {
                    Stepper("score \(draft.score)", value: $draft.score, in: -100_000...100_000)
                    Stepper("leftId \(draft.leftId)", value: $draft.leftId, in: 0...100_000)
                    Stepper("rightId \(draft.rightId)", value: $draft.rightId, in: 0...100_000)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                    }
                    .disabled(draft.isValid == false)
                }
            }
        }
    }
}

private enum LearningEditorRoute: Identifiable {
    case add
    case edit(LearningDictionaryEntry)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let entry):
            return entry.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .add:
            return "学習辞書を追加"
        case .edit:
            return "学習辞書を編集"
        }
    }

    var entry: LearningDictionaryEntry? {
        switch self {
        case .add:
            return nil
        case .edit(let entry):
            return entry
        }
    }

    var draft: DictionaryEntryDraft {
        switch self {
        case .add:
            return DictionaryEntryDraft(
                reading: "",
                word: "",
                score: DictionaryDefaultLexicalInfo.generalNoun.score,
                leftId: DictionaryDefaultLexicalInfo.generalNoun.leftId,
                rightId: DictionaryDefaultLexicalInfo.generalNoun.rightId
            )
        case .edit(let entry):
            return DictionaryEntryDraft(
                reading: entry.reading,
                word: entry.word,
                score: entry.score,
                leftId: entry.leftId,
                rightId: entry.rightId
            )
        }
    }
}

private enum UserEditorRoute: Identifiable {
    case add
    case edit(UserDictionaryEntry)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let entry):
            return entry.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .add:
            return "ユーザー辞書を追加"
        case .edit:
            return "ユーザー辞書を編集"
        }
    }

    var entry: UserDictionaryEntry? {
        switch self {
        case .add:
            return nil
        case .edit(let entry):
            return entry
        }
    }

    var draft: DictionaryEntryDraft {
        switch self {
        case .add:
            return DictionaryEntryDraft(
                reading: "",
                word: "",
                score: DictionaryDefaultLexicalInfo.generalNoun.score,
                leftId: DictionaryDefaultLexicalInfo.generalNoun.leftId,
                rightId: DictionaryDefaultLexicalInfo.generalNoun.rightId
            )
        case .edit(let entry):
            return DictionaryEntryDraft(
                reading: entry.reading,
                word: entry.word,
                score: entry.score,
                leftId: entry.leftId,
                rightId: entry.rightId
            )
        }
    }
}
