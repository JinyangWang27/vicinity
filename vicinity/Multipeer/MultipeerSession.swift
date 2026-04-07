import Foundation
import UIKit
import MultipeerConnectivity
import Combine

/// Manages all MultipeerConnectivity logic: advertising, browsing,
/// session handling, and message passing.
final class MultipeerSession: NSObject, ObservableObject {

    // MARK: - Published state

    @Published var peers: [Peer] = []
    @Published var receivedMessages: [String: [ReceivedMessage]] = [:]  // peerID → messages

    // MARK: - MC infrastructure

    private let serviceType = "vicinity-chat"  // max 15 chars, lowercase + hyphens only

    private let myPeerID: MCPeerID
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

    // MARK: - Callbacks

    /// Called when a regular chat message arrives (text, senderName, peerID).
    var onMessageReceived: ((String, String, String) -> Void)?

    /// Called when a handshake arrives from a newly connected peer (peerID, uuid, displayName).
    var onHandshakeReceived: ((String, String, String) -> Void)?

    /// Combine publisher for handshake events — allows multiple subscribers (services + views).
    let handshakePublisher = PassthroughSubject<(peerID: String, uuid: String, displayName: String), Never>()

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
    }

    // MARK: - Public API

    var myDisplayName: String { myPeerID.displayName }

    func connect(to peer: Peer) {
        browser.invitePeer(peer.peerID, to: session, withContext: nil, timeout: 30)
    }

    func send(text: String, to peer: Peer) {
        guard peer.isConnected,
              let data = text.data(using: .utf8) else { return }
        do {
            try session.send(data, toPeers: [peer.peerID], with: .reliable)
        } catch {
            print("[MultipeerSession] Failed to send message: \(error)")
        }
    }

    func disconnect(from peer: Peer) {
        session.cancelConnectPeer(peer.peerID)
    }

    /// Sends a message to a peer identified by display name (MCPeerID.displayName).
    /// Used by ScheduledMessageService which may not hold a Peer struct reference.
    func send(text: String, toPeerDisplayName displayName: String) {
        guard let peer = peers.first(where: { $0.id == displayName }),
              peer.isConnected else { return }
        send(text: text, to: peer)
    }

    // MARK: - Private helpers

    private func startAdvertising() {
        advertiser.startAdvertisingPeer()
    }

    private func startBrowsing() {
        browser.startBrowsingForPeers()
    }

    private func peer(for peerID: MCPeerID) -> Peer? {
        peers.first { $0.peerID == peerID }
    }

    private func updatePeer(_ peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let index = self.peers.firstIndex(where: { $0.peerID == peerID }) {
                self.peers[index].state = state
            }
        }
    }

    private func addPeerIfNeeded(_ peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.peers.contains(where: { $0.peerID == peerID }) {
                let peer = Peer(id: peerID.displayName, peerID: peerID, state: state)
                self.peers.append(peer)
            }
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
        updatePeer(peerID, state: state)
        if state == .connected {
            sendHandshake(to: peerID)
        }
    }

    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {

        // Intercept handshake messages before treating data as chat.
        if let map = try? JSONDecoder().decode([String: String].self, from: data),
           map["type"] == "handshake",
           let uuid = map["uuid"],
           let name = map["displayName"] {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updatePeerUUID(peerID, uuid: uuid, resolvedDisplayName: name)
                self.onHandshakeReceived?(peerID.displayName, uuid, name)
                self.handshakePublisher.send((peerID: peerID.displayName, uuid: uuid, displayName: name))
            }
            return
        }

        guard let text = String(data: data, encoding: .utf8) else { return }
        let senderName = peerID.displayName
        let peerIDString = peerID.displayName

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let msg = ReceivedMessage(text: text, senderName: senderName)
            self.receivedMessages[peerIDString, default: []].append(msg)
            self.onMessageReceived?(text, senderName, peerIDString)
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

    /// Auto-accept all incoming invitations from nearby peers.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        addPeerIfNeeded(peerID, state: .connecting)
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("[MultipeerSession] Advertising error: \(error)")
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
