import AppKit
@testable import Cadence
import Foundation
import SwiftUI
import Testing

extension AllTracksPerformanceTests {
    @Test(
        "A real 10k-row window reuses native row hosts while scrolling",
        .appKitExclusive
    )
    func realWindowScrollReusesNativeRowHosts() {
        let fixture = RealWindowTrackScrollFixture(tests: self)
        defer { fixture.finish() }

        fixture.verifyScrollLifecycle()
    }

    @Test(
        "Real-window scrolling attributes row-content and identity cost",
        .appKitExclusive
    )
    func realWindowScrollAttributesRowContentCost() {
        for contentMode in BenchmarkTrackRowContentMode.rowContentModes {
            let fixture = BenchmarkTrackScrollFixture(
                tests: self,
                contentMode: contentMode
            )
            fixture.verifyProfiles()
            fixture.finish()
        }
    }

    @Test("Track action menus materialize only for engaged rows")
    func actionMenuMaterializationRequiresEngagement() {
        let policy = TrackRowActionMenuMaterializationPolicy.production

        #expect(
            !policy.materializesFullActions(
                isHovered: false,
                isSelected: false,
                isFocused: false
            )
        )
        #expect(
            policy.materializesFullActions(
                isHovered: true,
                isSelected: false,
                isFocused: false
            )
        )
        #expect(
            policy.materializesFullActions(
                isHovered: false,
                isSelected: true,
                isFocused: true
            )
        )
        #expect(
            !policy.materializesFullActions(
                isHovered: false,
                isSelected: true,
                isFocused: false
            )
        )
    }

    @Test("Live scrolling defers hover-only track actions")
    func liveScrollingDefersHoverOnlyTrackActions() {
        let policy = TrackRowActionMenuMaterializationPolicy.production
        let interactionState = TrackTableInteractionState()

        interactionState.beginLiveScroll()
        #expect(
            !policy.materializesFullActions(
                isHovered: true,
                isSelected: false,
                isFocused: false,
                isLiveScrolling: interactionState.isLiveScrolling
            )
        )
        #expect(
            policy.materializesFullActions(
                isHovered: true,
                isSelected: false,
                isFocused: false,
                isKeyboardFocused: true,
                isLiveScrolling: true
            )
        )
        #expect(
            policy.materializesFullActions(
                isHovered: true,
                isSelected: false,
                isFocused: false,
                isAccessibilityFocused: true,
                isLiveScrolling: true
            )
        )

        interactionState.endLiveScroll()
        #expect(
            policy.materializesFullActions(
                isHovered: true,
                isSelected: false,
                isFocused: false,
                isLiveScrolling: interactionState.isLiveScrolling
            )
        )
    }

    @Test("Pointer scrolling preserves focused and accessibility interaction")
    func pointerScrollingPresentationPolicy() {
        #expect(
            TrackRowLiveScrollPresentation.resolve(
                isLiveScrolling: true,
                isSelected: false,
                isFocused: false,
                isControlFocused: false,
                isAccessibilityFocused: false,
                isAssistiveTechnologyEnabled: false
            ) == .pointerScrolling
        )
        #expect(
            TrackRowLiveScrollPresentation.resolve(
                isLiveScrolling: false,
                isSelected: false,
                isFocused: false,
                isControlFocused: false,
                isAccessibilityFocused: false,
                isAssistiveTechnologyEnabled: false
            ) == .interactive
        )
        for protectedPresentation in [
            TrackRowLiveScrollPresentation.resolve(
                isLiveScrolling: true,
                isSelected: true,
                isFocused: true,
                isControlFocused: false,
                isAccessibilityFocused: false,
                isAssistiveTechnologyEnabled: false
            ),
            TrackRowLiveScrollPresentation.resolve(
                isLiveScrolling: true,
                isSelected: false,
                isFocused: false,
                isControlFocused: true,
                isAccessibilityFocused: false,
                isAssistiveTechnologyEnabled: false
            ),
            TrackRowLiveScrollPresentation.resolve(
                isLiveScrolling: true,
                isSelected: false,
                isFocused: false,
                isControlFocused: false,
                isAccessibilityFocused: true,
                isAssistiveTechnologyEnabled: false
            ),
            TrackRowLiveScrollPresentation.resolve(
                isLiveScrolling: true,
                isSelected: false,
                isFocused: false,
                isControlFocused: false,
                isAccessibilityFocused: false,
                isAssistiveTechnologyEnabled: true
            ),
        ] {
            #expect(protectedPresentation == .interactive)
        }
        #expect(
            ProductionTrackTableRow.hoverStateAfterTrackIdentityChange(
                isHovered: true,
                isLiveScrolling: true
            )
        )
        #expect(
            !ProductionTrackTableRow.hoverStateAfterTrackIdentityChange(
                isHovered: true,
                isLiveScrolling: false
            )
        )
        #expect(
            ProductionTrackTableRow.lightweightFavoriteSymbolName(
                isFavorite: false
            ) == "heart"
        )
        #expect(
            ProductionTrackTableRow.lightweightFavoriteSymbolName(
                isFavorite: true
            ) == "heart.fill"
        )
        #expect(
            ProductionTrackTableRow.lightweightActionSymbolName
                == "ellipsis"
        )
        #expect(
            ProductionTrackTableRow.artworkOverlaySymbolName(
                isCurrentTrack: true,
                isPlaying: true
            ) == "waveform"
        )
        #expect(
            ProductionTrackTableRow.artworkOverlaySymbolName(
                isCurrentTrack: true,
                isPlaying: false
            ) == "play.fill"
        )
    }

    @Test("The track table follows native live-scroll notifications")
    func trackTableFollowsNativeLiveScrollNotifications() {
        let rows = makeTracks(count: 1)
        let core = makeCore(
            rows: rows,
            selection: .constant([]),
            probe: nil,
            sourceIndex: 590_100
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = TrackTableView()
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        coordinator.attach(tableView: tableView, scrollView: scrollView)

        #expect(!coordinator.interactionState.isLiveScrolling)
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
        #expect(!coordinator.interactionState.isLiveScrolling)
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        #expect(coordinator.interactionState.isLiveScrolling)
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
        #expect(!coordinator.interactionState.isLiveScrolling)
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
        #expect(!coordinator.interactionState.isLiveScrolling)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        #expect(coordinator.interactionState.isLiveScrolling)

        let replacementTableView = TrackTableView()
        let replacementScrollView = NSScrollView()
        replacementScrollView.documentView = replacementTableView
        coordinator.attach(
            tableView: replacementTableView,
            scrollView: replacementScrollView
        )
        #expect(!coordinator.interactionState.isLiveScrolling)
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        #expect(!coordinator.interactionState.isLiveScrolling)
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: replacementScrollView
        )
        #expect(coordinator.interactionState.isLiveScrolling)
        coordinator.detach()
        #expect(!coordinator.interactionState.isLiveScrolling)
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: replacementScrollView
        )
        #expect(!coordinator.interactionState.isLiveScrolling)
    }

    @Test(
        "Real-window scrolling measures lazy heavy track action menus",
        .appKitExclusive
    )
    func realWindowScrollMeasuresLazyActionMenus() {
        verifyActionMenuModes(
            BenchmarkTrackActionMenuMode.measurementOrder,
            pass: "forward"
        )
        verifyActionMenuModes(
            BenchmarkTrackActionMenuMode.measurementOrder.reversed(),
            pass: "reverse"
        )
    }

    @Test(
        "Pointer live scrolling materially reduces representative viewport work",
        .appKitExclusive
    )
    func realWindowScrollMeasuresSharedInteractionState() {
        let fixture = BenchmarkTrackScrollFixture(
            tests: self,
            contentMode: .fullStableIdentity,
            diagnosticLabel: "representative-live-scroll",
            columns: TrackTableColumn.allCases,
            menuCatalogItemCount: 100,
            usesWarmArtwork: true
        )
        defer { fixture.finish() }

        var idleP95Milliseconds: [Double] = []
        var liveP95Milliseconds: [Double] = []
        var idleMillisecondsPerConfiguration: [Double] = []
        var liveMillisecondsPerConfiguration: [Double] = []

        for round in 0 ..< 5 {
            let states = round.isMultiple(of: 2)
                ? [false, true]
                : [true, false]
            for isLiveScrolling in states {
                fixture.setLiveScrolling(isLiveScrolling)
                let stateLabel = isLiveScrolling ? "active" : "idle"
                let report = fixture.measureRepresentativeViewport(
                    expectedLiveScrolling: isLiveScrolling,
                    sampleCount: 20
                )
                print(
                    report.diagnostic(
                        mode: "representative-\(stateLabel)-round-\(round + 1)"
                    )
                )
                if isLiveScrolling {
                    liveP95Milliseconds.append(report.p95Milliseconds)
                    liveMillisecondsPerConfiguration.append(
                        report.millisecondsPerConfiguration
                    )
                } else {
                    idleP95Milliseconds.append(report.p95Milliseconds)
                    idleMillisecondsPerConfiguration.append(
                        report.millisecondsPerConfiguration
                    )
                }
            }
        }

        let idleMedianP95 = median(idleP95Milliseconds)
        let liveMedianP95 = median(liveP95Milliseconds)
        let idleMedianPerConfiguration = median(
            idleMillisecondsPerConfiguration
        )
        let liveMedianPerConfiguration = median(
            liveMillisecondsPerConfiguration
        )
        print(
            String(
                format: "representative-live-scroll-summary "
                    + "rounds=%d idle-median-p95=%.3fms "
                    + "live-median-p95=%.3fms idle-median-ms/config=%.3f "
                    + "live-median-ms/config=%.3f relative-p95=%.3f",
                idleP95Milliseconds.count,
                idleMedianP95,
                liveMedianP95,
                idleMedianPerConfiguration,
                liveMedianPerConfiguration,
                liveMedianP95 / max(idleMedianP95, 0.001)
            )
        )
        #expect(liveMedianP95 <= idleMedianP95 * 0.75)
        #expect(
            liveMedianPerConfiguration
                <= idleMedianPerConfiguration * 0.75
        )
    }

    @Test("Favorite transient state is scoped to its item and request token")
    func favoriteButtonTransientStateIsItemBound() {
        verifyFavoriteButtonTransientStateIsolation(tests: self)
    }

    @Test("An older favorite token cannot finish a newer reused item request")
    func favoriteButtonOlderTokenCannotFinishReusedItem() {
        verifyFavoriteButtonTokenReuseIsolation(tests: self)
    }

    @Test("A scheduled playback favorite stays bound to the displayed track")
    func scheduledPlaybackFavoriteStaysTrackBound() async throws {
        let fixture = try ProductionFavoritePlaybackFixture()
        try await fixture.startPlayback(at: fixture.firstTrackID)
        #expect(fixture.model.currentPlaybackTrack?.id == fixture.firstTrackID)
        let gate = ScheduledFavoriteActionGate()
        let displayedTrackID = fixture.firstTrackID
        let action = Task { @MainActor in
            await gate.suspend()
            return await fixture.model.setProductionPlaybackTrackFavorite(
                id: displayedTrackID,
                isFavorite: true
            )
        }
        await gate.waitUntilSuspended()

        try await fixture.startPlayback(at: fixture.secondTrackID)
        #expect(fixture.model.currentPlaybackTrack?.id == fixture.secondTrackID)
        await gate.resume()
        #expect(await action.value)

        #expect(
            fixture.model.librarySession.store.isTrackFavorite(
                fixture.firstTrackID
            )
        )
        #expect(
            !fixture.model.librarySession.store.isTrackFavorite(
                fixture.secondTrackID
            )
        )
        try await fixture.finish()
    }

    @Test(
        "A reused favorite control keeps one structural identity",
        .appKitExclusive
    )
    func reusedFavoriteButtonKeepsStructuralIdentity() {
        let fixture = FavoriteButtonReuseFixture()
        defer { fixture.finish() }

        fixture.verifyStructuralReuse()
    }

    private func verifyActionMenuModes(
        _ modes: some Sequence<BenchmarkTrackActionMenuMode>,
        pass: String
    ) {
        for mode in modes {
            let fixture = BenchmarkTrackScrollFixture(
                tests: self,
                contentMode: .fullStableIdentity,
                diagnosticLabel: "action-menu-\(pass)-\(mode.label)",
                columns: TrackTableColumn.allCases,
                menuCatalogItemCount: 100,
                actionMenuMaterializationPolicy: mode.policy
            )
            fixture.verifyProfiles()
            fixture.finish()
        }
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            return 0
        }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

@MainActor
private final class RealWindowTrackScrollFixture {
    private static let rowCount = 10000

    private let rows: [LibraryTrackProjection]
    private let probe: TrackTableWorkProbe
    private let core: TrackTableCore
    private let coordinator: TrackTableCore.Coordinator
    private let tableView: TrackTableView
    private let scrollView: NSScrollView
    private let window: NSWindow

    private var trackIDsByHost: [ObjectIdentifier: Set<UUID>] = [:]
    private var observedVisibleRows = 0
    private var maximumVisibleRows = 0

    init(tests: AllTracksPerformanceTests) {
        let rows = tests.makeTracks(count: Self.rowCount)
        let probe = TrackTableWorkProbe()
        let core = tests.makeCore(
            rows: rows,
            selection: .constant([]),
            probe: probe,
            sourceIndex: 590_000
        )
        let coordinator = TrackTableCore.Coordinator(parent: core)
        let tableView = TrackTableView()
        let viewport = NSRect(x: 0, y: 0, width: 900, height: 18 * 58)
        let scrollView = NSScrollView(frame: viewport)
        let window = NSWindow(
            contentRect: viewport,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.rows = rows
        self.probe = probe
        self.core = core
        self.coordinator = coordinator
        self.tableView = tableView
        self.scrollView = scrollView
        self.window = window

        configureTable(tableView, coordinator: coordinator)
        configureScrollView(scrollView, tableView: tableView)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        coordinator.attach(tableView: tableView, scrollView: scrollView)
        window.orderFront(nil)
        core.applyUpdate(to: scrollView, coordinator: coordinator)
        settleAppKit()
    }

    func finish() {
        coordinator.detach()
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    func verifyScrollLifecycle() {
        #expect(Thread.isMainThread)
        #expect(tableView.numberOfRows == Self.rowCount)
        recordVisibleHosts()
        let fullReloadsBeforeScrolling = probe.fullReloads
        for profile in RealWindowScrollProfile.allCases {
            let report = measure(profile)
            print(report.diagnostic(mode: "production"))
            verifyWatchdog(report)
        }
        let uniqueHostCount = trackIDsByHost.count
        let hostLimit = max(maximumVisibleRows * 3, 1)
        #expect(observedVisibleRows > 0)
        #expect(uniqueHostCount > 0)
        #expect(uniqueHostCount <= hostLimit)
        #expect(probe.hostingRootInstalls <= hostLimit)
        #expect(probe.hostingRootInstalls < probe.hostConfigurations)
        #expect(probe.hostConfigurations <= observedVisibleRows * 3)
        #expect(probe.hostConfigurations < Self.rowCount)
        #expect(probe.hostTrackIdentityChanges > 0)
        #expect(trackIDsByHost.values.contains { $0.count > 1 })
        #expect(probe.fullReloads == fullReloadsBeforeScrolling)
    }

    private func verifyWatchdog(_ report: RealWindowScrollTimingReport) {
        guard let watchdog = report.profile.productionWatchdogMilliseconds else {
            return
        }
        #expect(
            report.p95Milliseconds < watchdog,
            Comment(
                rawValue: "\(report.profile.label) p95 was "
                    + "\(report.p95Milliseconds) ms; "
                    + "the watchdog is \(watchdog) ms. "
                    + "Raw distribution: \(report.diagnostic(mode: "production"))"
            )
        )
    }

    private func measure(
        _ profile: RealWindowScrollProfile
    ) -> RealWindowScrollTimingReport {
        warmUp(profile)
        let configurationsBefore = probe.hostConfigurations
        let rootsBefore = probe.hostingRootInstalls
        let identityChangesBefore = probe.hostTrackIdentityChanges
        let durations = (0 ..< profile.sampleCount).map { _ in
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
            Issue.record("The real table did not expose a target row")
            return 0
        }
        return profile.targetRow(visibleRows: range, rowCount: Self.rowCount)
    }

    private func recordVisibleHosts() {
        let range = tableView.rows(in: scrollView.contentView.bounds)
        guard range.location != NSNotFound else {
            Issue.record("The real table did not expose a visible row range")
            return
        }
        let lowerBound = max(range.location, 0)
        let upperBound = min(range.location + range.length, rows.count)
        guard lowerBound < upperBound else {
            Issue.record("The real table exposed an empty visible row range")
            return
        }

        maximumVisibleRows = max(maximumVisibleRows, upperBound - lowerBound)
        observedVisibleRows += upperBound - lowerBound
        for row in lowerBound ..< upperBound {
            guard let cell = tableView.view(
                atColumn: 0,
                row: row,
                makeIfNecessary: false
            ) as? TrackTableHostingCell else {
                Issue.record("AppKit did not realize a host for visible row \(row)")
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

    private func configureTable(
        _ tableView: TrackTableView,
        coordinator: TrackTableCore.Coordinator
    ) {
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.rowHeight = 58
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        let column = NSTableColumn(
            identifier: TrackTableCore.Coordinator.columnIdentifier
        )
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
    }

    private func configureScrollView(
        _ scrollView: NSScrollView,
        tableView: TrackTableView
    ) {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        scrollView.contentView.postsBoundsChangedNotifications = true
    }
}
