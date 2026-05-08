import Foundation
import UIKit
import MultipeerConnectivity
import Combine

/// Manages all MultipeerConnectivity logic: advertising, browsing,
/// session handling, and message passing.
final class MultipeerSession: NSObject, ObservableObject {

    // MARK: - Published state

    @Published var peers: [Peer] = []
    @Published var receivedMessages: [String: [ReceivedMessage]] = [:]
    /// False when the advertiser or browser has failed and not yet recovered.
    @Published var isDiscoverable: Bool = true

    // MARK: - MC infrastructure

    private let serviceType = "vicinity-chat"  // max 15 chars, lowercase + hyphens only

    private var myPeerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser

    // MARK: - Device UUID (permanent identity)

    private let deviceUUID: String = {
        if let saved = UserDefaults.standard.string(forKey: "deviceUUID") { return saved }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "deviceUUID")
        return new
    }()

    /// Expose device UUID so views and utilities can read it without exposing the setter.
    var myDeviceUUID: String { deviceUUID }

    // MARK: - Combine publishers

    /// Emits (text, senderName, peerID) for every received chat message.
    let messagePublisher = PassthroughSubject<(text: String, senderName: String, peerID: String), Never>()

    /// Emits (peerID, uuid, displayName) when a handshake arrives from a newly connected peer.
    let handshakePublisher = PassthroughSubject<(peerID: String, uuid: String, displayName: String), Never>()

    // MARK: - Pending invitation

    @Published var pendingInvitationPeerName: String?
    private var pendingInvitationHandler: ((Bool, MCSession?) -> Void)?
    private var pendingInvitationTimeoutWork: DispatchWorkItem?

    // MARK: - Retry / reconnect tracking

    private var advertiserRetryDelay: TimeInterval = 2
    private var browserRetryDelay: TimeInterval = 2
    /// Previous MCSession state per peer — used to detect drop-from-connected.
    /// Keyed by MCPeerID rather than display name so two devices sharing a name don't
    /// corrupt each other's state tracking.
    private var peerPreviousState: [MCPeerID: MCSessionState] = [:]
    /// Auto-reconnect attempt count per peer. Reset on successful connect.
    private var autoReconnectAttempts: [MCPeerID: Int] = [:]
    private var heartbeatTimer: Timer?

    // MARK: - Init

    override init() {
        let displayName = UserDefaults.standard.string(forKey: "displayName")
            ?? UIDevice.current.name
        myPeerID = MCPeerID(displayName: displayName)

        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )

        browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: serviceType
        )

        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self

        startAdvertising()
        startBrowsing()
        startHeartbeat()
    }

    // MARK: - Public API

    var myDisplayName: String { myPeerID.displayName }

    func connect(to peer: Peer) {
        browser.invitePeer(peer.peerID, to: session, withContext: nil, timeout: 30)
    }

    /// Sends a chat message to a peer. Returns true if the framework accepted the send.
    @discardableResult
    func send(text: String, to peer: Peer) -> Bool {
        guard peer.isConnected,
              let data = text.data(using: .utf8) else { return false }
        do {
            try session.send(data, toPeers: [peer.peerID], with: .reliable)
            return true
        } catch {
            print("[MultipeerSession] Failed to send message: \(error)")
            return false
        }
    }

    func disconnect(from peer: Peer) {
        session.cancelConnectPeer(peer.peerID)
    }

    /// Accepts or rejects a pending connection invitation from a nearby peer.
    func respondToInvitation(_ accept: Bool) {
        pendingInvitationTimeoutWork?.cancel()
        pendingInvitationTimeoutWork = nil
        pendingInvitationHandler?(accept, accept ? session : nil)
        pendingInvitationHandler = nil
        DispatchQueue.main.async { [weak self] in
            self?.pendingInvitationPeerName = nil
        }
    }

    /// Restarts the MC stack with a new display name (called after onboarding or Settings change).
    /// Must be called on the main thread (all SwiftUI action callsites satisfy this).
    func updateDisplayName(_ name: String) {
        stopHeartbeat()
        advertiser.delegate = nil
        browser.delegate = nil
        session.delegate = nil
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()

        peers = []
        receivedMessages = [:]
        peerPreviousState = [:]
        autoReconnectAttempts = [:]

        myPeerID = MCPeerID(displayName: name)
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self

        advertiserRetryDelay = 2
        browserRetryDelay = 2

        startAdvertising()
        startBrowsing()
        startHeartbeat()
    }

    /// Sends a message to a peer identified by display name (MCPeerID.displayName).
    /// Used by ScheduledMessageService which may not hold a Peer struct reference.
    @discardableResult
    func send(text: String, toPeerDisplayName displayName: String) -> Bool {
        guard let peer = peers.first(where: { $0.displayName == displayName }),
              peer.isConnected else { return false }
        return send(text: text, to: peer)
    }

    // MARK: - Private: start/stop

    private func startAdvertising() {
        isDiscoverable = true
        advertiser.startAdvertisingPeer()
    }

    private func startBrowsing() {
        browser.startBrowsingForPeers()
    }

    // MARK: - Private: advertiser/browser retry with exponential backoff

    /// Must be called on the main queue. Mutates `advertiserRetryDelay`.
    private func scheduleAdvertiserRestart() {
        let delay = advertiserRetryDelay
        advertiserRetryDelay = min(advertiserRetryDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startAdvertising()
        }
    }

    /// Must be called on the main queue. Mutates `browserRetryDelay`.
    private func scheduleBrowserRestart() {
        let delay = browserRetryDelay
        browserRetryDelay = min(browserRetryDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startBrowsing()
        }
    }

    // MARK: - Private: auto-reconnect (max 3 attempts per peer)

    private func scheduleAutoReconnect(for peer: Peer) {
        let key = peer.peerID
        let attempts = autoReconnectAttempts[key, default: 0]
        guard attempts < 3 else { return }
        autoReconnectAttempts[key] = attempts + 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self,
                  let current = self.peers.first(where: { $0.peerID == peer.peerID }),
                  current.state == .notConnected else { return }
            self.connect(to: current)
        }
    }

    // MARK: - Private: heartbeat / keepalive

    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func sendHeartbeat() {
        let connectedPeerIDs = session.connectedPeers
        guard !connectedPeerIDs.isEmpty,
              let data = try? JSONEncoder().encode(["type": "ping"]) else { return }
        for peerID in connectedPeerIDs {
            do {
                try session.send(data, toPeers: [peerID], with: .reliable)
            } catch {
                // Stale connection — update state and trigger auto-reconnect.
                if let peer = peers.first(where: { $0.peerID == peerID }) {
                    updatePeer(peerID, state: .notConnected)
                    scheduleAutoReconnect(for: peer)
                }
            }
        }
    }

    // MARK: - Private: peer state helpers

    private func peer(for peerID: MCPeerID) -> Peer? {
        peers.first { $0.peerID == peerID }
    }

    private func updatePeer(_ peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let index = self.peers.firstIndex(where: { $0.peerID == peerID }) {
                self.peers[index].state = state
            } else if let index = self.peers.firstIndex(where: { $0.displayName == peerID.displayName }) {
                // Fallback: MCPeerID instance changed (e.g. lostPeer firing for an old instance).
                self.peers[index].state = state
            }
        }
    }

    private func addPeerIfNeeded(_ peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Primary: exact MCPeerID object already tracked — nothing to do.
            if self.peers.contains(where: { $0.peerID == peerID }) { return }

            // Secondary: same display name but a new MCPeerID instance (BLE rediscovery).
            if let index = self.peers.firstIndex(where: { $0.displayName == peerID.displayName }) {
                let existing = self.peers[index]
                if existing.state == .notConnected {
                    // Safe to replace: no live session on the old MCPeerID.
                    var replacement = Peer(peerID: peerID, state: state)
                    replacement.uuid = existing.uuid
                    replacement.resolvedDisplayName = existing.resolvedDisplayName
                    self.peers[index] = replacement
                    self.migratePeerKey(from: existing.peerID, to: peerID)
                } else if existing.state == .connecting {
                    // BLE produced a new MCPeerID while an invite is in-flight on the old one.
                    // Cancel the stale invite and swap in the fresh MCPeerID so the next
                    // connect() uses the right object.
                    self.session.cancelConnectPeer(existing.peerID)
                    var replacement = Peer(peerID: peerID, state: .notConnected)
                    replacement.uuid = existing.uuid
                    replacement.resolvedDisplayName = existing.resolvedDisplayName
                    self.peers[index] = replacement
                    self.migratePeerKey(from: existing.peerID, to: peerID)
                }
                // .connected: session is live on the old MCPeerID — leave it.
                return
            }

            // Genuinely new peer.
            self.peers.append(Peer(peerID: peerID, state: state))
        }
    }

    /// When BLE rediscovery replaces an MCPeerID instance for the same display name,
    /// move our state-tracking entries onto the new key so reconnect counters and
    /// previous-state history don't leak.
    private func migratePeerKey(from old: MCPeerID, to new: MCPeerID) {
        if let value = peerPreviousState.removeValue(forKey: old) {
            peerPreviousState[new] = value
        }
        if let value = autoReconnectAttempts.removeValue(forKey: old) {
            autoReconnectAttempts[new] = value
        }
    }

    private func removePeer(_ peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.peers.removeAll { $0.peerID == peerID }
        }
    }

    private func updatePeerUUID(_ peerID: MCPeerID, uuid: String, resolvedDisplayName: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let index = self.peers.firstIndex(where: { $0.peerID == peerID }) {
                self.peers[index].uuid = uuid
                self.peers[index].resolvedDisplayName = resolvedDisplayName
            }
        }
    }

    /// Sends our UUID + display name to the connected peer so they can persist our identity.
    private func sendHandshake(to peerID: MCPeerID) {
        let payload: [String: String] = [
            "type": "handshake",
            "uuid": deviceUUID,
            "displayName": myPeerID.displayName
        ]
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try session.send(data, toPeers: [peerID], with: .reliable)
        } catch {
            print("[MultipeerSession] Failed to send handshake: \(error)")
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerSession: MCSessionDelegate {

    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        // Send the handshake on the MC delegate queue (MCSession.send is thread-safe and
        // we want it dispatched as soon as the session reports .connected). Everything
        // that touches our state-tracking dictionaries is dispatched to main below so
        // those reads/writes are confined to a single queue.
        if state == .connected {
            sendHandshake(to: peerID)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let previousState = self.peerPreviousState[peerID]
            self.peerPreviousState[peerID] = state

            self.updatePeer(peerID, state: state)

            if state == .connected {
                self.autoReconnectAttempts[peerID] = 0
            } else if state == .notConnected, previousState == .connected {
                if let peer = self.peers.first(where: { $0.peerID == peerID }) {
                    self.scheduleAutoReconnect(for: peer)
                }
            }
        }
    }

    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {

        if let map = try? JSONDecoder().decode([String: String].self, from: data) {
            // Silently discard heartbeat pings.
            if map["type"] == "ping" { return }

            // Intercept handshake messages before treating data as chat.
            if map["type"] == "handshake",
               let uuid = map["uuid"],
               let name = map["displayName"] {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.updatePeerUUID(peerID, uuid: uuid, resolvedDisplayName: name)
                    self.handshakePublisher.send((peerID: peerID.displayName, uuid: uuid, displayName: name))
                }
                return
            }
        }

        guard let text = String(data: data, encoding: .utf8) else { return }
        let senderName = peerID.displayName
        let peerIDString = peerID.displayName

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let msg = ReceivedMessage(text: text, senderName: senderName)
            self.receivedMessages[peerIDString, default: []].append(msg)
            self.messagePublisher.send((text: text, senderName: senderName, peerID: peerIDString))
        }
    }

    // Unused delegate methods — required by protocol

    func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) {}

    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {

    /// Prompts the user to accept or decline an incoming invitation from a nearby peer.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingInvitationPeerName = peerID.displayName
            self.pendingInvitationHandler = { [weak self] accept, session in
                invitationHandler(accept, session)
                if accept {
                    self?.addPeerIfNeeded(peerID, state: .connecting)
                }
            }

            // Auto-decline if the user doesn't respond within 30 seconds.
            let work = DispatchWorkItem { [weak self] in
                self?.respondToInvitation(false)
            }
            self.pendingInvitationTimeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("[MultipeerSession] Advertising error: \(error)")
        DispatchQueue.main.async { [weak self] in
            self?.isDiscoverable = false
            self?.scheduleAdvertiserRestart()
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerSession: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        // A peer that reappears gets a fresh reconnect budget; otherwise three earlier
        // failed attempts would lock them out forever.
        DispatchQueue.main.async { [weak self] in
            self?.autoReconnectAttempts[peerID] = 0
        }
        addPeerIfNeeded(peerID, state: .notConnected)
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 lostPeer peerID: MCPeerID) {
        // Mark as disconnected rather than removing so users see the peer went away.
        // A clean disappearance shouldn't permanently consume the reconnect budget.
        DispatchQueue.main.async { [weak self] in
            self?.autoReconnectAttempts[peerID] = 0
        }
        updatePeer(peerID, state: .notConnected)
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        print("[MultipeerSession] Browsing error: \(error)")
        DispatchQueue.main.async { [weak self] in
            self?.isDiscoverable = false
            self?.scheduleBrowserRestart()
        }
    }
}

// MARK: - Supporting types

/// A lightweight in-memory received message used before SwiftData persistence.
struct ReceivedMessage: Identifiable {
    let id = UUID()
    let text: String
    let senderName: String
    let timestamp = Date()
}
