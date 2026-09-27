import Foundation
import agtermCore

/// Attaches remote panes again after their ssh lost the connection. `RemoteReconnectBook` owns the schedule;
/// this runs its probes on the remote tick and hands a pane whose host answered to `PaneLead.reconnect`.
extension ControlServer {
    static let reconnectProbeDeadline: TimeInterval = 10

    /// `session.reconnect`: a waiting pane retries now; a live one is parked as a lost link would park it, so
    /// the probe loop attaches it afresh without the claim and the hung ssh ends with its replaced surface.
    func reconnectSessionPane(_ target: String?, window: String?, pane: StatusPane?) -> ControlResponse {
        resolver.resolveSession(target, window: window) { store, id in
            guard let session = store.session(withID: id), session.remoteHost != nil, pane != .scratch else {
                return ControlResponse(ok: false, error: "pane is not attached from another Mac")
            }
            if pane == .right, session.splitSurface == nil {
                return ControlResponse(ok: false, error: "session has no split pane")
            }
            guard let view = (pane == .right ? session.splitSurface : session.surface) as? GhosttySurfaceView,
                  let identity = UUID(uuidString: view.paneToken) else {
                return ControlResponse(ok: false, error: "session not realized")
            }
            // a split opened on this Mac has no daemon in the binding
            guard session.remotePresentation?.binding.daemon(forLocalPane: identity) != nil else {
                return ControlResponse(ok: false, error: "pane is not attached from another Mac")
            }
            let book = RemoteReconnectBook.shared
            if !book.waiting(pane: identity) {
                let cover = PaneLead.cover(pane: identity)
                agtermApp.remotePaneStopped(view, store: store, sessionID: id, library: library)
                waitToReconnect(view, cover: cover)
            }
            // a probe just settled within the last minute still schedules a backoff; force it due now
            book.retryNow(pane: identity, now: hudClock())
            tickReconnects()
            return ControlResponse(ok: true, result: ControlResult(id: id.uuidString))
        }
    }

    /// A waiting pane shows its last screen over `cat`, which drops what it is sent: `session.type` and
    /// `session.paste` refuse rather than answer ok for text nobody reads. Reads stay available.
    func reconnectingRefusal(_ surface: GhosttySurfaceView) -> ControlResponse? {
        guard RemoteReconnectBook.shared.waiting(pane: UUID(uuidString: surface.paneToken)) else { return nil }
        return ControlResponse(ok: false, error: "pane is reconnecting")
    }

    func waitToReconnect(_ view: GhosttySurfaceView, cover: Bool) {
        guard let session = view.session, let host = session.remoteHost, heldSession(session.id) === session,
              let pane = session.surface === view ? session.paneIdentity
                  : session.splitSurface === view ? session.splitPaneIdentity : nil else { return }
        RemoteReconnectBook.shared.wait(pane: pane, session: session.id, host: host, cover: cover, now: hudClock())
        startRemoteTick()
    }

    func tickReconnects() {
        let book = RemoteReconnectBook.shared
        for pane in book.due(now: hudClock()) {
            guard let entry = book.entries[pane], waitingSurface(pane, in: entry.session) != nil,
                  let argv = try? RemoteSession.probeCommand(host: entry.host) else {
                book.cancel(pane: pane)
                continue
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await remoteRunner.run(argv, deadline: Self.reconnectProbeDeadline)
                guard let entry = book.finished(pane: pane, ok: result.status == 0, stderr: result.stderr,
                                                now: hudClock()),
                      let view = waitingSurface(pane, in: entry.session) else { return }
                // a row hidden for undo keeps waiting; finalizing its close lets the next due probe drop it
                guard let store = library.store(forSession: entry.session), PaneLead.reconnect?(view, entry.cover) == true else {
                    book.wait(pane: pane, session: entry.session, host: entry.host, cover: entry.cover, now: hudClock())
                    return
                }
                store.remotePaneResumed(pane, forSession: entry.session)
            }
        }
    }

    /// Every waiting pane and dropped stream retries now, not on its backoff.
    func retryRemoteLinksNow() {
        RemoteReconnectBook.shared.retryAllNow(now: hudClock())
        for client in remoteClients.values {
            client.retryNow()
            client.tick()
        }
        tickReconnects()
    }

    /// The surface still holding `pane`, nil once the pane or its row is gone. A row closed within its undo
    /// window still holds it.
    private func waitingSurface(_ pane: UUID, in sessionID: UUID) -> GhosttySurfaceView? {
        guard let session = heldSession(sessionID) else { return nil }
        let surface = session.paneIdentity == pane ? session.surface
            : session.splitPaneIdentity == pane ? session.splitSurface : nil
        return surface as? GhosttySurfaceView
    }

    private func heldSession(_ id: UUID) -> Session? {
        guard let store = library.store(holdingSession: id) else { return nil }
        return store.session(withID: id) ?? store.pendingCloseSession(withID: id)
    }
}
