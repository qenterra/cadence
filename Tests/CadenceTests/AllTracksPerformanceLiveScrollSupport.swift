import AppKit
@testable import Cadence
import Foundation
import SwiftUI
import Testing

enum BenchmarkTrackRowContentMode {
    case simpleHost
    case fullStableIdentity
    case fullResetIdentity

    static let rowContentModes: [Self] = [
        .simpleHost,
        .fullStableIdentity,
        .fullResetIdentity,
    ]
    var label: String {
        switch self {
        case .simpleHost: "simple-host"
        case .fullStableIdentity: "current"
        case .fullResetIdentity: "full-row-reset-identity"
        }
    }
}

enum BenchmarkTrackActionMenuMode {
    case alwaysMaterialized
    case productionLazy

    static let measurementOrder: [Self] = [
        .alwaysMaterialized,
        .productionLazy,
    ]

    var label: String {
        switch self {
        case .alwaysMaterialized: "always"
        case .productionLazy: "lazy"
        }
    }

    var policy: TrackRowActionMenuMaterializationPolicy {
        switch self {
        case .alwaysMaterialized: .always
        case .productionLazy: .production
        }
    }
}

private func makeBenchmarkWarmArtworkData() -> Data {
    guard
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let data = representation.representation(
            using: .png,
            properties: [:]
        )
    else {
        preconditionFailure("The warm artwork fixture must encode PNG data")
    }
    return data
}

@MainActor
final class BenchmarkTrackScrollFixture {
    private static let rowCount = 10000
    private static let p95WatchdogMilliseconds = 250.0

    private let rows: [LibraryTrackProjection]
    private let contentMode: BenchmarkTrackRowContentMode
    private let diagnosticLabel: String
    private let probe = TrackTableWorkProbe()
    private let artworkWorkProbe: ProductionArtworkWorkProbe?
    private let interactionState: TrackTableInteractionState
    private let rowSource: BenchmarkTrackRowSource
    private let tableView = TrackTableView()
    private let scrollView: NSScrollView
    private let window: NSWindow

    private var trackIDsByHost: [ObjectIdentifier: Set<UUID>] = [:]
    private var maximumVisibleRows = 0

    init(
        tests: AllTracksPerformanceTests,
        contentMode: BenchmarkTrackRowContentMode,
        diagnosticLabel: String? = nil,
        columns: [TrackTableColumn] = [],
        menuCatalogItemCount: Int = 0,
        usesWarmArtwork: Bool = false,
        isLiveScrolling: Bool = false,
        actionMenuMaterializationPolicy:
        TrackRowActionMenuMaterializationPolicy = .production
    ) {
        let baseRows = tests.makeTracks(count: Self.rowCount)
        let warmArtworkID = tests.deterministicUUID(591_001)
        let rows = if usesWarmArtwork {
            baseRows.map {
                tests.replacingArtworkID($0, with: warmArtworkID)
            }
        } else {
            baseRows
        }
        let artworkWorkProbe = usesWarmArtwork
            ? ProductionArtworkWorkProbe()
            : nil
        let warmArtworkData = usesWarmArtwork
            ? makeBenchmarkWarmArtworkData()
            : Data()
        let artworkLoader: ProductionArtworkLoader? = if usesWarmArtwork {
            { artworkID, variant in
                ArtworkAsset(
                    id: artworkID,
                    data: warmArtworkData,
                    variant: variant
                )
            }
        } else {
            nil
        }
        let snapshot = tests.makeSnapshot(
            rows: rows,
            version: TrackTableContentVersion(
                sourceID: tests.deterministicUUID(591_000),
                generation: 0
            )
        )
        let viewport = NSRect(x: 0, y: 0, width: 900, height: 18 * 58)
        let scrollView = NSScrollView(frame: viewport)
        let window = NSWindow(
            contentRect: viewport,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let model = Self.makeModel(
            tests: tests,
            menuCatalogItemCount: menuCatalogItemCount
        )
        let interactionState = TrackTableInteractionState()
        if isLiveScrolling {
            interactionState.beginLiveScroll()
        }

        self.rows = rows
        self.contentMode = contentMode
        self.diagnosticLabel = diagnosticLabel ?? contentMode.label
        self.artworkWorkProbe = artworkWorkProbe
        self.interactionState = interactionState
        rowSource = BenchmarkTrackRowSource(
            rows: rows,
            model: model,
            queueIDProvider: TrackTableQueueIDProvider(snapshot: snapshot),
            widths: tests.presentation.widths,
            contentMode: contentMode,
            columns: columns,
            actionMenuMaterializationPolicy:
            actionMenuMaterializationPolicy,
            artworkLoader: artworkLoader,
            artworkWorkProbe: artworkWorkProbe,
            interactionState: interactionState,
            probe: probe
        )
        self.scrollView = scrollView
        self.window = window

        configureTable()
        configureScrollView()
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFront(nil)
        tableView.reloadData()
        settleAppKit()
        settleWarmArtwork()
    }

    private static func makeModel(
        tests: AllTracksPerformanceTests,
        menuCatalogItemCount: Int
    ) -> CadenceAppModel {
        guard menuCatalogItemCount > 0 else {
            return tests.presentationModel
        }
        let model = CadenceAppModel.testFixture()
        model.librarySession.store.tags = (0 ..< menuCatalogItemCount).map { index in
            LibraryTagProjection(
                id: tests.deterministicUUID(700_000 + index),
                displayPath: "Benchmark Tag \(index)",
                groupPath: "Benchmark"
            )
        }
        model.librarySession.store.playlists = (0 ..< menuCatalogItemCount).map { index in
            LibraryPlaylistProjection(
                id: tests.deterministicUUID(710_000 + index),
                name: "Benchmark Playlist \(index)",
                trackCount: index,
                totalDuration: TimeInterval(index * 180),
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                customArtworkID: nil
            )
        }
        return model
    }

    func finish() {
        interactionState.endLiveScroll()
        tableView.dataSource = nil
        tableView.delegate = nil
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    func verifyProfiles() {
        #expect(tableView.numberOfRows == Self.rowCount)
        recordVisibleHosts()
        for profile in RealWindowScrollProfile.allCases {
            let report = measure(profile)
            print(report.diagnostic(mode: diagnosticLabel))
            #expect(report.newConfigurations > 0)
            verifyWatchdog(report)
        }

        let hostLimit = max(maximumVisibleRows * 3, 1)
        #expect(!trackIDsByHost.isEmpty)
        #expect(trackIDsByHost.count <= hostLimit)
        #expect(probe.hostingRootInstalls <= hostLimit)
        #expect(probe.hostingRootInstalls < probe.hostConfigurations)
        #expect(probe.hostTrackIdentityChanges > 0)
        #expect(trackIDsByHost.values.contains { $0.count > 1 })
    }

    func setLiveScrolling(_ isLiveScrolling: Bool) {
        let wasLiveScrolling = interactionState.isLiveScrolling
        let changesBefore = probe.liveScrollPresentationChanges
        let activationsBefore = probe.lightweightPresentationActivations
        let artworkTaskStartsBefore = artworkWorkProbe?.taskStarts
        let artworkPublicationsBefore =
            artworkWorkProbe?.publishedArtworkIDs.count
        if isLiveScrolling {
            interactionState.beginLiveScroll()
        } else {
            interactionState.endLiveScroll()
        }
        settleAppKit()
        settleWarmArtwork()
        rowSource.verifyRepresentativeContext(
            expectedLiveScrolling: isLiveScrolling
        )
        if wasLiveScrolling != isLiveScrolling {
            #expect(probe.liveScrollPresentationChanges > changesBefore)
            if isLiveScrolling {
                #expect(
                    probe.lightweightPresentationActivations
                        > activationsBefore
                )
            }
            if let artworkWorkProbe,
               let artworkTaskStartsBefore,
               let artworkPublicationsBefore {
                #expect(
                    artworkWorkProbe.taskStarts
                        == artworkTaskStartsBefore
                )
                #expect(
                    artworkWorkProbe.publishedArtworkIDs.count
                        == artworkPublicationsBefore
                )
            }
        }
    }

    func measureRepresentativeViewport(
        expectedLiveScrolling: Bool,
        sampleCount: Int
    ) -> RealWindowScrollTimingReport {
        let artworkTaskStartsBefore = artworkWorkProbe?.taskStarts
        let artworkPublicationsBefore =
            artworkWorkProbe?.publishedArtworkIDs.count
        rowSource.resetConfiguredInteractionStates()
        rowSource.verifyRepresentativeContext(
            expectedLiveScrolling: expectedLiveScrolling
        )
        let report = measure(
            .viewportJumps,
            sampleCount: sampleCount
        )
        rowSource.verifyConfiguredInteractionStates(
            expectedLiveScrolling: expectedLiveScrolling
        )
        if let artworkWorkProbe,
           let artworkTaskStartsBefore,
           let artworkPublicationsBefore {
            #expect(
                artworkWorkProbe.taskStarts == artworkTaskStartsBefore
            )
            #expect(
                artworkWorkProbe.publishedArtworkIDs.count
                    == artworkPublicationsBefore
            )
        }
        return report
    }

    private func verifyWatchdog(_ report: RealWindowScrollTimingReport) {
        #expect(
            report.p95Milliseconds < Self.p95WatchdogMilliseconds,
            Comment(
                rawValue: "\(diagnosticLabel) \(report.profile.label) p95 was "
                    + "\(report.p95Milliseconds) ms; the watchdog is "
                    + "\(Self.p95WatchdogMilliseconds) ms. Raw distribution: "
                    + report.diagnostic(mode: diagnosticLabel)
            )
        )
    }

    private func measure(
        _ profile: RealWindowScrollProfile,
        sampleCount: Int? = nil
    ) -> RealWindowScrollTimingReport {
        warmUp(profile)
        let configurationsBefore = probe.hostConfigurations
        let rootsBefore = probe.hostingRootInstalls
        let identityChangesBefore = probe.hostTrackIdentityChanges
        let durations = (0 ..< (sampleCount ?? profile.sampleCount)).map { _ in
            let row = targetRow(for: profile)
            let start = DispatchTime.now().uptimeNanoseconds
            tableView.scrollRowToVisible(row)
            settleAppKit()
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            recordVisibleHosts()
            return Double(elapsed) / 1_000_000
        }
        return RealWindowScrollTimingReport(
            profile: profile,
            durations: durations,
            newConfigurations: probe.hostConfigurations - configurationsBefore,
            newRoots: probe.hostingRootInstalls - rootsBefore,
            identityChanges: probe.hostTrackIdentityChanges
                - identityChangesBefore
        )
    }

    private func warmUp(_ profile: RealWindowScrollProfile) {
        tableView.scrollRowToVisible(profile.warmupRow)
        settleAppKit()
        recordVisibleHosts()
        for _ in 0 ..< 3 {
            tableView.scrollRowToVisible(targetRow(for: profile))
            settleAppKit()
            recordVisibleHosts()
        }
    }

    private func targetRow(for profile: RealWindowScrollProfile) -> Int {
        let range = tableView.rows(in: scrollView.contentView.bounds)
        guard range.location != NSNotFound else {
            Issue.record("The benchmark table did not expose a target row")
            return 0
        }
        return profile.targetRow(visibleRows: range, rowCount: Self.rowCount)
    }

    private func recordVisibleHosts() {
        let range = tableView.rows(in: scrollView.contentView.bounds)
        guard range.location != NSNotFound else {
            Issue.record("The benchmark table did not expose visible rows")
            return
        }
        let lowerBound = max(range.location, 0)
        let upperBound = min(range.location + range.length, rows.count)
        maximumVisibleRows = max(maximumVisibleRows, upperBound - lowerBound)
        for row in lowerBound ..< upperBound {
            guard let cell = tableView.view(
                atColumn: 0,
                row: row,
                makeIfNecessary: false
            ) as? BenchmarkTrackHostingCell else {
                Issue.record("AppKit did not realize benchmark row \(row)")
                continue
            }
            #expect(cell.hostState.trackID == rows[row].id)
            trackIDsByHost[ObjectIdentifier(cell), default: []]
                .insert(rows[row].id)
        }
    }

    private func settleAppKit() {
        scrollView.layoutSubtreeIfNeeded()
        tableView.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        _ = RunLoop.main.run(
            mode: .default,
            before: Date(timeIntervalSinceNow: 0.001)
        )
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private func settleWarmArtwork() {
        guard let artworkWorkProbe else {
            return
        }
        for _ in 0 ..< 20 where artworkWorkProbe.taskStarts == 0
            || artworkWorkProbe.publishedArtworkIDs.count
            != artworkWorkProbe.taskStarts {
            settleAppKit()
        }
        #expect(artworkWorkProbe.taskStarts > 0)
        #expect(
            artworkWorkProbe.publishedArtworkIDs.count
                == artworkWorkProbe.taskStarts
        )
    }
}

private extension BenchmarkTrackScrollFixture {
    func configureTable() {
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.rowHeight = 58
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = rowSource
        tableView.delegate = rowSource
        let column = NSTableColumn(identifier: BenchmarkTrackRowSource.columnID)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
    }

    func configureScrollView() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
    }
}

@MainActor
private final class BenchmarkTrackRowSource: NSObject,
    NSTableViewDataSource,
    NSTableViewDelegate {
    static let columnID = NSUserInterfaceItemIdentifier("Benchmark.Track.Row")
    private static let cellID = NSUserInterfaceItemIdentifier(
        "Benchmark.Track.HostingCell"
    )

    private let rows: [LibraryTrackProjection]
    private let model: CadenceAppModel
    private let queueIDProvider: TrackTableQueueIDProvider
    private let widths: TrackTableResolvedWidths
    private let contentMode: BenchmarkTrackRowContentMode
    private let columns: [TrackTableColumn]
    private let actionMenuMaterializationPolicy:
        TrackRowActionMenuMaterializationPolicy
    private let artworkLoader: ProductionArtworkLoader?
    private let artworkWorkProbe: ProductionArtworkWorkProbe?
    private let interactionState: TrackTableInteractionState
    private let probe: TrackTableWorkProbe
    private var configuredInteractionStates: Set<Bool> = []

    init(
        rows: [LibraryTrackProjection],
        model: CadenceAppModel,
        queueIDProvider: TrackTableQueueIDProvider,
        widths: TrackTableResolvedWidths,
        contentMode: BenchmarkTrackRowContentMode,
        columns: [TrackTableColumn],
        actionMenuMaterializationPolicy:
        TrackRowActionMenuMaterializationPolicy,
        artworkLoader: ProductionArtworkLoader?,
        artworkWorkProbe: ProductionArtworkWorkProbe?,
        interactionState: TrackTableInteractionState,
        probe: TrackTableWorkProbe
    ) {
        self.rows = rows
        self.model = model
        self.queueIDProvider = queueIDProvider
        self.widths = widths
        self.contentMode = contentMode
        self.columns = columns
        self.actionMenuMaterializationPolicy =
            actionMenuMaterializationPolicy
        self.artworkLoader = artworkLoader
        self.artworkWorkProbe = artworkWorkProbe
        self.interactionState = interactionState
        self.probe = probe
    }

    func numberOfRows(in _: NSTableView) -> Int {
        rows.count
    }

    func verifyRepresentativeContext(expectedLiveScrolling: Bool) {
        #expect(columns == TrackTableColumn.allCases)
        #expect(model.librarySession.store.tags.count == 100)
        #expect(model.librarySession.store.playlists.count == 100)
        #expect(interactionState.isLiveScrolling == expectedLiveScrolling)
        if artworkLoader != nil {
            #expect(rows.allSatisfy { $0.artworkID != nil })
            #expect(Set(rows.compactMap(\.artworkID)).count == 1)
            #expect(artworkWorkProbe != nil)
        }
    }

    func verifyConfiguredInteractionStates(expectedLiveScrolling: Bool) {
        #expect(configuredInteractionStates == [expectedLiveScrolling])
    }

    func resetConfiguredInteractionStates() {
        configuredInteractionStates.removeAll(keepingCapacity: true)
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor _: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let cell = tableView.makeView(
            withIdentifier: Self.cellID,
            owner: nil
        ) as? BenchmarkTrackHostingCell ?? makeCell()
        let track = rows[row]
        configuredInteractionStates.insert(
            interactionState.isLiveScrolling
        )
        cell.configure(
            .track(
                TrackTableRowConfiguration(
                    model: model,
                    track: track,
                    queueIDProvider: queueIDProvider,
                    columns: columns,
                    widths: widths,
                    playlistID: nil,
                    queueSource: .allTracks,
                    reorderAction: nil,
                    resolveDraggedTrackIDs: { $0 },
                    actionTrackIDs: [track.id],
                    isSelected: false,
                    isFocused: false,
                    artworkLoader: artworkLoader,
                    artworkWorkProbe: artworkWorkProbe,
                    interactionState: interactionState,
                    workProbe: probe,
                    select: {}
                )
            )
        )
        return cell
    }

    private func makeCell() -> BenchmarkTrackHostingCell {
        let cell = BenchmarkTrackHostingCell(
            contentMode: contentMode,
            actionMenuMaterializationPolicy:
            actionMenuMaterializationPolicy,
            probe: probe
        )
        cell.identifier = Self.cellID
        return cell
    }
}
