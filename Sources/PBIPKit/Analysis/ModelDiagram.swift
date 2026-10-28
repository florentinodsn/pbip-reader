import Foundation

/// Diagramme du modèle : rôle de chaque table et position de sa boîte.
/// Calcul pur, sans interface : l'application ne fait que dessiner les boîtes et les liens.
public struct ModelDiagram: Equatable, Sendable {
    /// Rôle déduit des relations : une table de faits est du côté « plusieurs » sans jamais être
    /// du côté « un » ; une dimension est du côté « un » d'au moins une relation.
    public enum Role: String, Sendable {
        case fact, dimension, isolated
    }

    public enum Layout: String, CaseIterable, Sendable {
        /// Faits en haut, dimensions à gauche, tables sans relation à part.
        case grid
        /// Chaque table de faits au centre, ses dimensions autour, les dimensions de dimensions
        /// (flocon) sur un second anneau.
        case star
    }

    public struct Node: Equatable, Sendable {
        public var table: String
        public var role: Role
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        /// Colonnes affichées dans la boîte (les colonnes des relations d'abord si tout ne tient pas).
        public var rows: [String]
        public var hiddenRowCount: Int
        public var measureCount: Int

        public var centerX: Double { x + width / 2 }
        public var centerY: Double { y + height / 2 }
    }

    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Tracé d'une relation : ligne brisée du côté `from` (premier point) au côté `to` (dernier point),
    /// sur les bords des boîtes.
    public struct Edge: Equatable, Sendable {
        /// Indice dans `SemanticModel.relationships`.
        public var relationship: Int
        public var points: [Point]
    }

    public var layout: Layout
    public var nodes: [Node]
    public var edges: [Edge]
    public var width: Double
    public var height: Double

    public func node(_ table: String) -> Node? {
        nodes.first { $0.table == table } ?? nodes.first { $0.table.caseInsensitiveCompare(table) == .orderedSame }
    }

    // MARK: - Dimensions des boîtes

    public static let nodeWidth = 200.0
    public static let headerHeight = 30.0
    public static let rowHeight = 18.0
    public static let maxRows = 12
    static let gap = 60.0
    static let margin = 40.0

    // MARK: - Rôles

    public static func roles(_ model: SemanticModel) -> [String: Role] {
        var many = Set<String>(), one = Set<String>()
        for r in model.relationships {
            let from = canonical(r.from.table, in: model), to = canonical(r.to.table, in: model)
            if r.fromCardinality == "one" { one.insert(from) } else { many.insert(from) }
            if r.toCardinality == "one" { one.insert(to) } else { many.insert(to) }
        }
        var roles: [String: Role] = [:]
        for t in model.tables {
            roles[t.name] = one.contains(t.name) ? .dimension : many.contains(t.name) ? .fact : .isolated
        }
        return roles
    }

    // MARK: - Disposition

    public static func make(_ model: SemanticModel, layout: Layout) -> ModelDiagram {
        let roles = roles(model)
        let keyColumns = Set(model.relationships.flatMap { [$0.from, $0.to] }.map {
            ColumnRef(table: canonical($0.table, in: model), column: $0.column.lowercased())
        })
        var sized: [String: Node] = [:]
        for t in model.tables {
            sized[t.name] = box(t, role: roles[t.name] ?? .isolated, keys: keyColumns)
        }
        let order = model.tables.map(\.name)
        var nodes: [Node]
        switch layout {
        case .grid: nodes = grid(order, sized)
        case .star: nodes = star(order, sized, neighbors: neighbors(model))
        }
        // Coordonnées positives, avec une marge autour.
        let minX = nodes.map(\.x).min() ?? 0, minY = nodes.map(\.y).min() ?? 0
        for i in nodes.indices {
            nodes[i].x += margin - minX
            nodes[i].y += margin - minY
        }
        let width = (nodes.map { $0.x + $0.width }.max() ?? 0) + margin
        let height = (nodes.map { $0.y + $0.height }.max() ?? 0) + margin
        var diagram = ModelDiagram(layout: layout, nodes: nodes, edges: [], width: width, height: height)
        diagram.edges = diagram.route(model)
        return diagram
    }

    // MARK: - Tracé des liens

    func route(_ model: SemanticModel) -> [Edge] {
        var edges: [Edge] = []
        var straight: [(index: Int, a: Node, b: Node)] = []
        var channel: [(index: Int, dim: Node, fact: Node, dimIsFrom: Bool)] = []

        // En grille, une dimension placée à gauche et sous la table de faits est reliée par un couloir :
        // sortie à droite, montée dans l'espace entre colonnes, passage sous la rangée des faits.
        let factBottom = nodes.filter { $0.role == .fact }.map { $0.y + $0.height }.max()
        for (i, r) in model.relationships.enumerated() {
            guard let a = node(r.from.table), let b = node(r.to.table), a.table != b.table else { continue }
            if layout == .grid, let factBottom {
                if a.role == .fact, b.y >= factBottom, b.x + b.width <= a.x {
                    channel.append((i, b, a, false))
                    continue
                }
                if b.role == .fact, a.y >= factBottom, a.x + a.width <= b.x {
                    channel.append((i, a, b, true))
                    continue
                }
            }
            straight.append((i, a, b))
        }

        if let factBottom, !channel.isEmpty {
            let top = nodes.filter { $0.role != .fact }.map(\.y).min() ?? factBottom + Self.gap
            let laneSpace = max(top - factBottom - 16, 8)
            let laneStep = min(14, laneSpace / Double(max(channel.count - 1, 1)))
            var perColumn: [Double: Int] = [:]
            var perFact: [String: Int] = [:]
            let total = Dictionary(grouping: channel, by: { $0.fact.table }).mapValues(\.count)
            let ordered = channel.sorted { ($0.dim.x, $0.dim.y) < ($1.dim.x, $1.dim.y) }
            for (k, c) in ordered.enumerated() {
                let column = c.dim.x + c.dim.width
                let j = perColumn[column, default: 0]
                perColumn[column] = j + 1
                let f = perFact[c.fact.table, default: 0]
                perFact[c.fact.table] = f + 1
                let laneX = column + 12 + Double(j) * min(14, (Self.gap - 24) / 3)
                let busY = factBottom + 12 + Double(k) * laneStep
                let anchorX = c.fact.x + c.fact.width * Double(f + 1) / Double((total[c.fact.table] ?? 1) + 1)
                var points = [
                    Point(x: c.dim.x + c.dim.width, y: c.dim.centerY),
                    Point(x: laneX, y: c.dim.centerY),
                    Point(x: laneX, y: busY),
                    Point(x: anchorX, y: busY),
                    Point(x: anchorX, y: c.fact.y + c.fact.height),
                ]
                if !c.dimIsFrom { points.reverse() }
                edges.append(Edge(relationship: c.index, points: points))
            }
        }

        // Lignes droites ; plusieurs relations entre les deux mêmes tables sont décalées en parallèle.
        let pairKey = { (s: (index: Int, a: Node, b: Node)) in [s.a.table, s.b.table].sorted().joined(separator: "\u{0}") }
        let groups = Dictionary(grouping: straight, by: pairKey)
        for s in straight {
            let group = groups[pairKey(s)] ?? []
            let rank = Double(group.firstIndex { $0.index == s.index } ?? 0) - Double(group.count - 1) / 2
            let ca = Point(x: s.a.centerX, y: s.a.centerY), cb = Point(x: s.b.centerX, y: s.b.centerY)
            let length = max(hypot(cb.x - ca.x, cb.y - ca.y), 1)
            let dx = -(cb.y - ca.y) / length * rank * 16, dy = (cb.x - ca.x) / length * rank * 16
            let sa = Point(x: ca.x + dx, y: ca.y + dy), sb = Point(x: cb.x + dx, y: cb.y + dy)
            edges.append(Edge(relationship: s.index, points: [Self.border(s.a, from: sa, toward: sb), Self.border(s.b, from: sb, toward: sa)]))
        }
        return edges.sorted { $0.relationship < $1.relationship }
    }

    /// Point où le segment `from → toward` sort du rectangle de la boîte.
    static func border(_ n: Node, from p: Point, toward q: Point) -> Point {
        let dx = q.x - p.x, dy = q.y - p.y
        let tx = dx == 0 ? Double.infinity : (dx > 0 ? n.x + n.width - p.x : n.x - p.x) / dx
        let ty = dy == 0 ? Double.infinity : (dy > 0 ? n.y + n.height - p.y : n.y - p.y) / dy
        let t = max(0, min(tx, ty, 1))
        return Point(x: p.x + dx * t, y: p.y + dy * t)
    }

    static func box(_ table: Table, role: Role, keys: Set<ColumnRef>) -> Node {
        let names = table.columns.map(\.name)
        var rows = names
        if names.count > maxRows {
            let isKey = { (n: String) in keys.contains(ColumnRef(table: table.name, column: n.lowercased())) }
            let key = names.filter(isKey).prefix(maxRows)
            let fill = names.filter { !isKey($0) }.prefix(maxRows - key.count)
            let chosen = Set(key).union(fill)
            rows = names.filter { chosen.contains($0) }
        }
        let hidden = names.count - rows.count
        let footer = hidden > 0 || !table.measures.isEmpty
        let height = headerHeight + Double(rows.count) * rowHeight + (footer ? rowHeight : 0) + 8
        return Node(table: table.name, role: role, x: 0, y: 0, width: nodeWidth, height: height,
                    rows: rows, hiddenRowCount: hidden, measureCount: table.measures.count)
    }

    /// Faits sur une rangée en haut, dimensions en colonnes à gauche, tables isolées en grille à droite.
    static func grid(_ order: [String], _ sized: [String: Node]) -> [Node] {
        let all = order.compactMap { sized[$0] }
        let facts = all.filter { $0.role == .fact }
        let dims = all.filter { $0.role == .dimension }
        let others = all.filter { $0.role == .isolated }
        let step = nodeWidth + gap
        let perColumn = 6
        let dimColumns = dims.isEmpty ? 0 : (dims.count + perColumn - 1) / perColumn
        let left = Double(dimColumns) * step

        var result: [Node] = []
        var y = 0.0
        // Rangées de faits (5 par rangée).
        for chunk in stride(from: 0, to: facts.count, by: 5) {
            let row = facts[chunk..<min(chunk + 5, facts.count)]
            for (i, var n) in row.enumerated() {
                n.x = left + Double(i) * step
                n.y = y
                result.append(n)
            }
            y += (row.map(\.height).max() ?? 0) + gap
        }
        // Un peu plus d'espace sous les faits : les liens des dimensions y passent.
        let top = facts.isEmpty ? 0 : y + gap / 2
        // Colonnes de dimensions.
        for c in 0..<dimColumns {
            var cy = top
            for var n in dims.dropFirst(c * perColumn).prefix(perColumn) {
                n.x = Double(c) * step
                n.y = cy
                cy += n.height + gap / 2
                result.append(n)
            }
        }
        // Tables isolées, 4 par rangée, à droite des dimensions et sous les faits.
        var oy = top
        for chunk in stride(from: 0, to: others.count, by: 4) {
            let row = others[chunk..<min(chunk + 4, others.count)]
            for (i, var n) in row.enumerated() {
                n.x = left + Double(i) * step
                n.y = oy
                result.append(n)
            }
            oy += (row.map(\.height).max() ?? 0) + gap
        }
        return result
    }

    /// Une grappe par table de faits : la table au centre, ses dimensions sur une ellipse autour,
    /// les dimensions rattachées à une dimension (flocon) sur une ellipse plus large, dans le même angle.
    static func star(_ order: [String], _ sized: [String: Node], neighbors: [String: [String]]) -> [Node] {
        var placed = Set<String>()
        var clusters: [[Node]] = []

        for name in order where sized[name]?.role == .fact {
            guard var fact = sized[name] else { continue }
            placed.insert(name)
            let ring = (neighbors[name] ?? []).filter { !placed.contains($0) && sized[$0]?.role == .dimension }
            ring.forEach { placed.insert($0) }

            let dimW = ring.compactMap { sized[$0]?.width }.max() ?? nodeWidth
            let dimH = ring.compactMap { sized[$0]?.height }.max() ?? 0
            var rx = fact.width / 2 + dimW / 2 + gap * 1.5
            var ry = fact.height / 2 + dimH / 2 + gap
            // Assez de périmètre pour que les boîtes voisines ne se chevauchent pas.
            let needed = Double(ring.count) * (dimW + gap / 2)
            let perimeter = Double.pi * (rx + ry)
            if needed > perimeter {
                rx *= needed / perimeter
                ry *= needed / perimeter
            }

            fact.x = -fact.width / 2
            fact.y = -fact.height / 2
            var cluster = [fact]
            var frontier: [(name: String, angle: Double)] = []
            for (i, d) in ring.enumerated() {
                // Décalage d'un demi-pas : deux dimensions à gauche et à droite plutôt qu'en colonne.
                let step = 2 * Double.pi / Double(max(ring.count, 1))
                let angle = -Double.pi / 2 + (ring.count > 1 ? step / 2 : 0) + step * Double(i)
                guard var n = sized[d] else { continue }
                n.x = rx * cos(angle) - n.width / 2
                n.y = ry * sin(angle) - n.height / 2
                cluster.append(n)
                frontier.append((d, angle))
            }

            // Anneaux suivants : dimensions de dimensions.
            var level = 1
            while !frontier.isEmpty {
                var next: [(name: String, angle: Double)] = []
                let lrx = rx + Double(level) * (dimW + gap * 1.5)
                let lry = ry + Double(level) * (dimH + gap)
                for parent in frontier {
                    let children = (neighbors[parent.name] ?? []).filter { !placed.contains($0) && sized[$0]?.role != .fact }
                    children.forEach { placed.insert($0) }
                    for (i, c) in children.enumerated() {
                        let angle = parent.angle + (Double(i) - Double(children.count - 1) / 2) * 0.3
                        guard var n = sized[c] else { continue }
                        n.x = lrx * cos(angle) - n.width / 2
                        n.y = lry * sin(angle) - n.height / 2
                        cluster.append(n)
                        next.append((c, angle))
                    }
                }
                frontier = next
                level += 1
            }
            clusters.append(cluster)
        }

        // Grappes côte à côte, alignées en haut.
        var result: [Node] = []
        var offsetX = 0.0
        for cluster in clusters {
            let minX = cluster.map(\.x).min() ?? 0, minY = cluster.map(\.y).min() ?? 0
            let maxX = cluster.map { $0.x + $0.width }.max() ?? 0
            for var n in cluster {
                n.x += offsetX - minX
                n.y -= minY
                result.append(n)
            }
            offsetX += maxX - minX + gap * 2
        }

        // Le reste (dimensions sans fait, tables isolées) sur une rangée en dessous.
        let bottom = (result.map { $0.y + $0.height }.max() ?? -gap) + gap * 2
        var rest = order.filter { !placed.contains($0) }.compactMap { sized[$0] }
        var x = 0.0, y = bottom, rowHeight = 0.0
        let rowWidth = max(offsetX, 4 * (nodeWidth + gap))
        for i in rest.indices {
            if x > 0, x + rest[i].width > rowWidth {
                x = 0
                y += rowHeight + gap
                rowHeight = 0
            }
            rest[i].x = x
            rest[i].y = y
            x += rest[i].width + gap
            rowHeight = max(rowHeight, rest[i].height)
        }
        return result + rest
    }

    static func neighbors(_ model: SemanticModel) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for r in model.relationships {
            let a = canonical(r.from.table, in: model), b = canonical(r.to.table, in: model)
            guard a != b else { continue }
            if !(result[a] ?? []).contains(b) { result[a, default: []].append(b) }
            if !(result[b] ?? []).contains(a) { result[b, default: []].append(a) }
        }
        return result
    }

    /// Nom de table tel que déclaré dans le modèle (les références sont insensibles à la casse).
    static func canonical(_ name: String, in model: SemanticModel) -> String {
        model.table(named: name)?.name ?? name
    }
}
