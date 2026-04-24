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
    /// Previous MCSession state per peer (keyed by display name) — used to detect drop-from-connected.
    private var peerPreviousState: [String: MCSessionState] = [:]
    /// Auto-reconnect attempt count per peer (keyed by display name). Reset on successful connect.
    private var autoReconnectAttempts: [String: Int] = [:]
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
        guard let peer = peers.first(where: { $0.id == displayName }),
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

    private func scheduleAdvertiserRestart() {
        let delay = advertiserRetryDelay
        advertiserRetryDelay = min(advertiserRetryDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startAdvertising()
        }
    }

    private func scheduleBrowserRestart() {
        let delay = browserRetryDelay
        browserRetryDelay = min(browserRetryDelay * 2, 30)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startBrowsing()
        }
    }

    // MARK: - Private: auto-reconnect (max 3 attempts per peer)

    private func scheduleAutoReconnect(for peer: Peer) {
        let attempts = autoReconnectAttempts[peer.id, default: 0]
        guard attempts < 3 else { return }
        autoReconnectAttempts[peer.id] = attempts + 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self,
                  let current = self.peers.first(where: { $0.id == peer.id }),
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
            } else if let index = self.peers.firstIndex(where: { $0.id == peerID.displayName }) {
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
            if let index = self.peers.firstIndex(where: { $0.id == peerID.displayName }) {
                let existing = self.peers[index]
                if existing.state == .notConnected {
                    // Safe to replace: no live session on the old MCPeerID.
                    var replacement = Peer(id: peerID.displayName, peerID: peerID, state: state)
                    replacement.uuid = existing.uuid
                    replacement.resolvedDisplayName = existing.resolvedDisplayName
                    self.peers[index] = replacement
                } else if existing.state == .connecting {
                    // BLE produced a new MCPeerID while an invite is in-flight on the old one.
                    // Cancel the stale invite and swap in the fresh MCPeerID so the next
                    // connect() uses the right object.
                    self.session.cancelConnectPeer(existing.peerID)
                    var replacement = Peer(id: peerID.displayName, peerID: peerID, state: .notConnected)
                    replacement.uuid = existing.uuid
                    replacement.resolvedDisplayName = existing.resolvedDisplayName
                    self.peers[index] = replacement
                }
                // .connected: session is live on the old MCPeerID — leave it.
                return
            }

            // Genuinely new peer.
            self.peers.append(Peer(id: peerID.displayName, peerID: peerID, state: state))
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
        let previousState = peerPreviousState[peerID.displayName]
        peerPreviousState[peerID.displayName] = state

        updatePeer(peerID, state: state)

        if state == .connected {
            autoReconnectAttempts[peerID.displayName] = 0
            sendHandshake(to: peerID)
        } else if state == .notConnected, previousState == .connected {
            // Peer dropped from an established connection — schedule auto-reconnect.
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let peer = self.peers.first(where: { $0.id == peerID.displayName }) else { return }
                self.scheduleAutoReconnect(for: peer)
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
        DispatchQueue.main.async { self.isDiscoverable = false }
        scheduleAdvertiserRestart()
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerSession: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        addPeerIfNeeded(peerID, state: .notConnected)
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 lostPeer peerID: MCPeerID) {
        // Mark as disconnected rather than removing so users see the peer went away
        updatePeer(peerID, state: .notConnected)
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        print("[MultipeerSession] Browsing error: \(error)")
        DispatchQueue.main.async { self.isDiscoverable = false }
        scheduleBrowserRestart()
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
