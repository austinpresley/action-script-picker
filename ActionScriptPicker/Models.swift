import Foundation

struct LoadedAction: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
}

struct LoadedActionSet: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let actions: [LoadedAction]
}

struct ActionCatalog: Equatable, Sendable {
    let sets: [LoadedActionSet]

    static let empty = ActionCatalog(sets: [])
}

struct ActionSelection: Equatable, Sendable {
    var setID: Int?
    var actionID: Int?

    static let empty = ActionSelection(setID: nil, actionID: nil)
}

enum ActionCatalogParser {
    private struct Envelope: Decodable {
        let sets: [RawSet]
    }

    private struct RawSet: Decodable {
        let name: String
        let actions: [RawAction]
    }

    private struct RawAction: Decodable {
        let name: String
    }

    static func parse(_ json: String) throws -> ActionCatalog {
        guard let data = json.data(using: .utf8) else {
            throw CatalogParsingError.invalidUTF8
        }

        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            let sets = envelope.sets.enumerated().map { setIndex, rawSet in
                LoadedActionSet(
                    id: setIndex,
                    name: rawSet.name,
                    actions: rawSet.actions.enumerated().map { actionIndex, rawAction in
                        LoadedAction(id: actionIndex, name: rawAction.name)
                    }
                )
            }
            return ActionCatalog(sets: sets)
        } catch {
            throw CatalogParsingError.malformedResponse(error.localizedDescription)
        }
    }
}

enum CatalogParsingError: LocalizedError, Equatable {
    case invalidUTF8
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return String(localized: "Photoshop returned text that could not be read as UTF-8.")
        case .malformedResponse:
            return String(localized: "Photoshop returned incomplete or malformed action data.")
        }
    }

    var details: String {
        switch self {
        case .invalidUTF8:
            return "The action query result was not valid UTF-8."
        case .malformedResponse(let details):
            return details
        }
    }
}

enum SelectionResolver {
    static func initialSelection(for catalog: ActionCatalog) -> ActionSelection {
        guard let firstSet = catalog.sets.first else { return .empty }
        return ActionSelection(setID: firstSet.id, actionID: firstSet.actions.first?.id)
    }

    static func selection(
        afterReplacing oldCatalog: ActionCatalog,
        oldSelection: ActionSelection,
        with newCatalog: ActionCatalog
    ) -> ActionSelection {
        guard
            let oldSetID = oldSelection.setID,
            let oldSet = oldCatalog.sets.first(where: { $0.id == oldSetID }),
            let matchingSet = newCatalog.sets.first(where: { $0.name == oldSet.name })
        else {
            return initialSelection(for: newCatalog)
        }

        guard
            let oldActionID = oldSelection.actionID,
            let oldAction = oldSet.actions.first(where: { $0.id == oldActionID }),
            let matchingAction = matchingSet.actions.first(where: { $0.name == oldAction.name })
        else {
            return ActionSelection(setID: matchingSet.id, actionID: matchingSet.actions.first?.id)
        }

        return ActionSelection(setID: matchingSet.id, actionID: matchingAction.id)
    }
}

struct Ambiguity: Equatable, Sendable {
    let message: String
}

enum AmbiguityAnalyzer {
    static func ambiguity(
        for action: LoadedAction,
        in set: LoadedActionSet,
        catalog: ActionCatalog
    ) -> Ambiguity? {
        if set.name.isEmpty {
            return Ambiguity(message: String(localized: "This action set has no name. Rename it in Photoshop, then Refresh."))
        }
        if action.name.isEmpty {
            return Ambiguity(message: String(localized: "This action has no name. Rename it in Photoshop, then Refresh."))
        }
        if catalog.sets.filter({ $0.name == set.name }).count > 1 {
            return Ambiguity(message: String(localized: "More than one action set has this name. Rename one in Photoshop, then Refresh."))
        }
        if set.actions.filter({ $0.name == action.name }).count > 1 {
            return Ambiguity(message: String(localized: "More than one action in this set has this name. Rename one in Photoshop, then Refresh."))
        }
        return nil
    }

    static func setIsAmbiguous(_ set: LoadedActionSet, catalog: ActionCatalog) -> Bool {
        set.name.isEmpty || catalog.sets.filter { $0.name == set.name }.count > 1
    }
}

enum ActionSearch {
    static func filter(_ actions: [LoadedAction], query: String) -> [LoadedAction] {
        guard !query.isEmpty else { return actions }
        return actions.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

struct RefreshSnapshot: Equatable, Sendable {
    var catalog: ActionCatalog
    var dataTargetID: String?
    var isStale: Bool
    var selection: ActionSelection

    static let empty = RefreshSnapshot(
        catalog: .empty,
        dataTargetID: nil,
        isStale: false,
        selection: .empty
    )
}

enum RefreshReducer {
    static func success(
        previous: RefreshSnapshot,
        targetID: String,
        catalog: ActionCatalog
    ) -> RefreshSnapshot {
        let selection: ActionSelection
        if previous.dataTargetID == targetID {
            selection = SelectionResolver.selection(
                afterReplacing: previous.catalog,
                oldSelection: previous.selection,
                with: catalog
            )
        } else {
            selection = SelectionResolver.initialSelection(for: catalog)
        }
        return RefreshSnapshot(
            catalog: catalog,
            dataTargetID: targetID,
            isStale: false,
            selection: selection
        )
    }

    static func failure(previous: RefreshSnapshot, targetID: String) -> RefreshSnapshot {
        guard previous.dataTargetID == targetID, !previous.catalog.sets.isEmpty else {
            return .empty
        }
        var retained = previous
        retained.isStale = true
        return retained
    }
}
