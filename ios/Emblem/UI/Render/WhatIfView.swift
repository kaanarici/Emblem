import SwiftUI
import EmblemCore

indirect enum WhatIfExpr: Hashable {
    case number(Double)
    case variable(String)
    case binary(Character, WhatIfExpr, WhatIfExpr)
    case call(String, [WhatIfExpr])

    func eval(_ vars: [String: Double]) -> Double? {
        switch self {
        case .number(let v): return v
        case .variable(let name): return vars[name]
        case .binary(let op, let lhs, let rhs):
            guard let a = lhs.eval(vars), let b = rhs.eval(vars) else { return nil }
            switch op {
            case "+": return a + b
            case "-": return a - b
            case "*": return a * b
            case "/": return a / b
            case "^": return pow(a, b)
            default: return nil
            }
        case .call(let name, let args):
            let values = args.compactMap { $0.eval(vars) }
            guard values.count == args.count else { return nil }
            switch (name, values.count) {
            case ("sqrt", 1): return values[0] < 0 ? nil : sqrt(values[0])
            case ("min", 2...): return values.min()
            case ("max", 2...): return values.max()
            default: return nil
            }
        }
    }

    var variables: Set<String> {
        switch self {
        case .number: []
        case .variable(let name): [name]
        case .binary(_, let lhs, let rhs): lhs.variables.union(rhs.variables)
        case .call(_, let args): args.reduce(into: []) { $0.formUnion($1.variables) }
        }
    }
}

struct WhatIfParser {
    private let src: [Character]
    private var pos = 0

    static func parse(_ text: String) -> WhatIfExpr? {
        var parser = WhatIfParser(src: Array(text))
        guard let expr = parser.expr() else { return nil }
        parser.skipSpace()
        return parser.pos == parser.src.count ? expr : nil
    }

    private mutating func expr() -> WhatIfExpr? {
        guard var lhs = term() else { return nil }
        while let op = match("+-") {
            guard let rhs = term() else { return nil }
            lhs = .binary(op, lhs, rhs)
        }
        return lhs
    }

    private mutating func term() -> WhatIfExpr? {
        guard var lhs = unary() else { return nil }
        while let op = match("*/") {
            guard let rhs = unary() else { return nil }
            lhs = .binary(op, lhs, rhs)
        }
        return lhs
    }

    private mutating func unary() -> WhatIfExpr? {
        if match("-") != nil {
            guard let operand = unary() else { return nil }
            return .binary("-", .number(0), operand)
        }
        return power()
    }

    private mutating func power() -> WhatIfExpr? {
        guard let base = primary() else { return nil }
        if match("^") != nil {
            guard let exponent = unary() else { return nil }
            return .binary("^", base, exponent)
        }
        return base
    }

    private mutating func primary() -> WhatIfExpr? {
        skipSpace()
        guard pos < src.count else { return nil }
        let c = src[pos]

        if c.isNumber || c == "." {
            var text = ""
            while pos < src.count, src[pos].isNumber || src[pos] == "." {
                text.append(src[pos])
                pos += 1
            }
            return Double(text).map(WhatIfExpr.number)
        }

        if c.isLetter || c == "_" {
            var name = ""
            while pos < src.count, src[pos].isLetter || src[pos].isNumber || src[pos] == "_" {
                name.append(src[pos])
                pos += 1
            }
            if match("(") != nil {
                var args: [WhatIfExpr] = []
                repeat {
                    guard let arg = expr() else { return nil }
                    args.append(arg)
                } while match(",") != nil
                guard match(")") != nil else { return nil }
                return .call(name.lowercased(), args)
            }
            return .variable(name)
        }

        if c == "(" {
            pos += 1
            guard let inner = expr(), match(")") != nil else { return nil }
            return inner
        }
        return nil
    }

    private mutating func match(_ candidates: String) -> Character? {
        skipSpace()
        guard pos < src.count, candidates.contains(src[pos]) else { return nil }
        defer { pos += 1 }
        return src[pos]
    }

    private mutating func skipSpace() {
        while pos < src.count, src[pos] == " " { pos += 1 }
    }
}

struct WhatIfView: View {
    @Environment(\.blockInteraction) private var blockInteraction
    let block: WhatIfBlock
    private let parsed: [(label: String, expr: WhatIfExpr, unit: String?)]?
    @State private var values: [String: Double]

    init(block: WhatIfBlock) {
        self.block = block
        let names = Set(block.variables.map(\.name))
        var defaults: [String: Double] = [:]
        var valid = !block.variables.isEmpty && !block.outputs.isEmpty
        for variable in block.variables {
            guard variable.min < variable.max else { valid = false; break }
            defaults[variable.name] = Swift.min(Swift.max(variable.defaultValue, variable.min), variable.max)
        }
        var outputs: [(String, WhatIfExpr, String?)] = []
        for output in block.outputs {
            guard let expr = WhatIfParser.parse(output.expression),
                  expr.variables.isSubset(of: names)
            else { valid = false; break }
            outputs.append((output.label, expr, output.unit))
        }
        parsed = valid ? outputs : nil
        _values = State(initialValue: defaults)
    }

    var body: some View {
        if let parsed {
            let hasTitle = !(block.title ?? "").isEmpty
            VStack(spacing: 3) {
                if let title = block.title, hasTitle {
                    Text(title)
                        .font(Theme.cardTitle())
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .seamCard(.top)
                }

                VStack(alignment: .leading, spacing: 22) {
                    outputRow(parsed)
                    VStack(spacing: 18) {
                        ForEach(block.variables, id: \.name) { variable in
                            sliderRow(variable)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .seamCard(hasTitle ? .bottom : .solo)
            }
            .padding(.horizontal, Theme.contentMargin)
        }
    }

    private func outputRow(_ outputs: [(label: String, expr: WhatIfExpr, unit: String?)]) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(outputs.enumerated()), id: \.offset) { _, output in
                let value = output.expr.eval(values)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value.map { format($0, unit: output.unit) } ?? "–")
                        .font(.system(size: 27, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .animation(.smooth(duration: 0.25), value: value)
                    Text(output.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sliderRow(_ variable: WhatIfBlock.Variable) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text(variable.label)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(format(values[variable.name] ?? variable.defaultValue, unit: variable.unit))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            if let step = variable.step {
                Slider(value: binding(variable), in: variable.min...variable.max, step: step)
                    .blockActivationControl()
                    .accentTint(Theme.accentDark)
            } else {
                Slider(value: binding(variable), in: variable.min...variable.max)
                    .blockActivationControl()
                    .accentTint(Theme.accentDark)
            }
        }
    }

    private func binding(_ variable: WhatIfBlock.Variable) -> Binding<Double> {
        Binding(
            get: { values[variable.name] ?? variable.defaultValue },
            set: { value in
                blockInteraction.performActivation { values[variable.name] = value }
            })
    }

    private func format(_ value: Double, unit: String?) -> String {
        guard value.isFinite else { return "–" }
        let number = abs(value) >= 100 || value == value.rounded()
            ? value.formatted(.number.precision(.fractionLength(0)))
            : value.formatted(.number.precision(.fractionLength(0...1)))
        guard let unit, !unit.isEmpty else { return number }
        if ["$", "€", "£", "¥"].contains(unit) {
            return value < 0 ? "-\(unit)\(number.replacingOccurrences(of: "-", with: ""))" : unit + number
        }
        return unit.count == 1 || unit.hasPrefix("°") ? number + unit : "\(number) \(unit)"
    }
}
