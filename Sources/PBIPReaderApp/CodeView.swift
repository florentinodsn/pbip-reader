import PBIPKit
import SwiftUI

/// Visionneuse DAX / M : police à chasse fixe, coloration simple, texte sélectionnable.
struct CodeView: View {
    let code: String
    let language: SyntaxTokenizer.Language

    var body: some View {
        ScrollView(.horizontal) {
            Text(highlighted)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    var highlighted: AttributedString {
        // Les tabulations sont affichées sur 4 espaces pour une indentation lisible.
        let source = code.replacingOccurrences(of: "\t", with: "    ")
        var result = AttributedString()
        for token in SyntaxTokenizer.tokenize(source, language: language) {
            var piece = AttributedString(token.text)
            piece.foregroundColor = Self.color(token.kind)
            if token.kind == .keyword { piece.font = .system(.callout, design: .monospaced).bold() }
            result += piece
        }
        return result
    }

    static func color(_ kind: SyntaxTokenizer.Kind) -> Color {
        switch kind {
        case .plain: return .primary
        case .keyword: return .purple
        case .function: return .blue
        case .string: return .red
        case .number: return .orange
        case .comment: return .green
        case .reference: return .teal
        case .table: return .brown
        }
    }
}
