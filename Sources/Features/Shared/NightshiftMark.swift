import SwiftUI

/// The app's mark – crescent moon with a pair of beamed eighth notes.
///
/// Drawn as vectors so it takes the accent colour and stays crisp at any size.
/// The geometry is the same one the app icon is rastered from; regenerate both
/// from `Tools/make-icon.py` (`--swift` prints these constants) so they can
/// never drift apart.
struct NightshiftMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                crescent(side)
                // Each part is filled on its own. Merged into one path they
                // would share a non-zero winding rule, and where a stem
                // overlaps its note head the two contours cancel out – that
                // is what punched the notches into the notes.
                NotesShape(part: .heads).fill()
                NotesShape(part: .stems).fill()
                NotesShape(part: .beam).fill()
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Moon disc with the bite punched out. `destinationOut` inside a
    /// compositing group does the subtraction without path boolean ops.
    private func crescent(_ side: CGFloat) -> some View {
        ZStack {
            disc(Geometry.moonCentre, Geometry.moonRadius, side)
            disc(Geometry.biteCentre, Geometry.biteRadius, side)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }

    private func disc(_ centre: CGPoint, _ radius: CGFloat, _ side: CGFloat) -> some View {
        Circle()
            .frame(width: radius * 2 * side, height: radius * 2 * side)
            .position(x: centre.x * side, y: centre.y * side)
    }

    enum Geometry {
        static let moonCentre = CGPoint(x: 0.4314, y: 0.4963)
        static let moonRadius: CGFloat = 0.3048
        static let biteCentre = CGPoint(x: 0.5711, y: 0.3587)
        static let biteRadius: CGFloat = 0.2921
        static let head1 = CGPoint(x: 0.6108, y: 0.4612)
        static let head2 = CGPoint(x: 0.7919, y: 0.4145)
        static let headRX: CGFloat = 0.0662
        static let headRY: CGFloat = 0.0526
        static let headTilt: CGFloat = -0.3200
        static let stem1 = (CGPoint(x: 0.6638, y: 0.4612), CGPoint(x: 0.6663, y: 0.2587))
        static let stem2 = (CGPoint(x: 0.8449, y: 0.4145), CGPoint(x: 0.8474, y: 0.2120))
        static let beam = (CGPoint(x: 0.6663, y: 0.2719), CGPoint(x: 0.8474, y: 0.2251))
        static let stemWidth: CGFloat = 0.0263
        static let beamWidth: CGFloat = 0.0526
    }
}

/// One part of the note pair. Stems and beam are stroked lines with round
/// caps – the outline of such a stroke is exactly the capsule the icon
/// rasteriser draws.
private struct NotesShape: Shape {
    enum Part { case heads, stems, beam }

    let part: Part

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        // The first layout pass can hand out a zero or invalid size, and
        // stroking with a zero line width is not worth finding out about.
        guard side.isFinite, side > 0 else { return Path() }
        let originX = rect.midX - side / 2
        let originY = rect.midY - side / 2
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: originX + p.x * side, y: originY + p.y * side)
        }

        switch part {
        case .heads:
            var path = Path()
            path.addPath(head(NightshiftMark.Geometry.head1, side: side, place: point))
            path.addPath(head(NightshiftMark.Geometry.head2, side: side, place: point))
            return path

        case .stems:
            var lines = Path()
            for segment in [NightshiftMark.Geometry.stem1, NightshiftMark.Geometry.stem2] {
                lines.move(to: point(segment.0))
                lines.addLine(to: point(segment.1))
            }
            return lines.strokedPath(
                StrokeStyle(lineWidth: NightshiftMark.Geometry.stemWidth * side,
                            lineCap: .round))

        case .beam:
            var beam = Path()
            beam.move(to: point(NightshiftMark.Geometry.beam.0))
            beam.addLine(to: point(NightshiftMark.Geometry.beam.1))
            return beam.strokedPath(
                StrokeStyle(lineWidth: NightshiftMark.Geometry.beamWidth * side,
                            lineCap: .round))
        }
    }

    private func head(_ centre: CGPoint, side: CGFloat,
                      place: (CGPoint) -> CGPoint) -> Path {
        let c = place(centre)
        let rx = NightshiftMark.Geometry.headRX * side
        let ry = NightshiftMark.Geometry.headRY * side
        let box = CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)
        let rotation = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: NightshiftMark.Geometry.headTilt)
            .translatedBy(x: -c.x, y: -c.y)
        var path = Path()
        path.addEllipse(in: box, transform: rotation)
        return path
    }
}
