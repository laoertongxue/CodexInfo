import Foundation

/// Compares the route of a turn with the route the user selected.
///
/// The design (5.6.3) keeps the two cases apart. A route that differs from the
/// selection is reported as evidence ("路由不一致"), but it only counts toward
/// the degraded verdict when the two routes are comparable and the actual one
/// is the lower one ("路由降档"). A model swap is not a downgrade: the model
/// tiers are only comparable inside one family with a known tier, so a
/// different model is a mismatch and never a downgrade.
public enum RouteComparison {
    /// The order of the reasoning efforts (design 5.6.3).
    static let effortOrder: [String: Int] = [
        "low": 0,
        "medium": 1,
        "high": 2,
        "xhigh": 3,
    ]

    /// The known lower tiers of a model family, from the lowest to the highest.
    ///
    /// A model whose name carries no tier keyword is the base tier of its
    /// family. A name that carries an unknown keyword belongs to the family
    /// itself, so two models of different families cannot be compared and the
    /// route is only reported as a mismatch.
    static let modelTiers: [String: Int] = [
        "nano": 0,
        "mini": 1,
    ]

    /// The rank of the base tier of a model family.
    static let baseModelTier = 2

    /// Whether the route of the turn is comparable and lower than the selection.
    ///
    /// - Parameters:
    ///   - actualModel: the model the turn really ran on.
    ///   - actualEffort: the reasoning effort the turn really ran with.
    ///   - selectedModel: the model the user selected.
    ///   - selectedEffort: the reasoning effort the user selected.
    public static func isDowngrade(
        actualModel: String?,
        actualEffort: String?,
        selectedModel: String?,
        selectedEffort: String?
    ) -> Bool {
        if let actual = actualEffort, let selected = selectedEffort, actual != selected,
           let actualRank = effortRank(actual), let selectedRank = effortRank(selected),
           actualRank < selectedRank {
            return true
        }
        if let actual = actualModel, let selected = selectedModel, actual != selected,
           case .ordered(let actualIsLower) = compareModels(actual, selected),
           actualIsLower {
            return true
        }
        return false
    }

    /// The rank of a reasoning effort, or `nil` when the name is not known.
    static func effortRank(_ effort: String) -> Int? {
        effortOrder[normalize(effort)]
    }

    /// The rank of a model inside its family, or `nil` when the tier is unknown.
    ///
    /// The name is split at its last dash: the head is the family and the tail
    /// is the tier. A name without a dash is the base tier of its family.
    static func modelRank(_ model: String) -> Int? {
        let parts = split(model)
        guard let tier = parts.tier else { return baseModelTier }
        return modelTiers[tier]
    }

    /// The family and the tier of a model name.
    ///
    /// Only a known tier keyword names a tier. Every other name belongs to the
    /// family, so two models of different families never compare.
    static func split(_ model: String) -> (family: String, tier: String?) {
        guard let index = model.lastIndex(of: "-") else { return (model, nil) }
        let tier = String(model[model.index(after: index)...]).lowercased()
        guard modelTiers[tier] != nil else { return (model, nil) }
        return (String(model[model.startIndex..<index]), tier)
    }

    /// The comparison of two model names.
    static func compareModels(_ actual: String, _ selected: String) -> Comparison {
        let actualParts = split(actual)
        let selectedParts = split(selected)
        guard actualParts.family == selectedParts.family else { return .incomparable }
        guard let actualRank = modelRank(actual), let selectedRank = modelRank(selected) else {
            return .incomparable
        }
        if actualRank == selectedRank { return .incomparable }
        return .ordered(actualIsLower: actualRank < selectedRank)
    }

    /// Normalizes a tier name: the letters decide, the separators do not.
    static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// The outcome of the comparison of two comparable values.
enum Comparison {
    /// The two values have an order.
    case ordered(actualIsLower: Bool)
    /// The two values cannot be compared.
    case incomparable
}
