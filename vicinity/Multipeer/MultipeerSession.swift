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

    // Closure called when a message arrives so views can persist it
    var onMessageReceived: ((String, String, String) -> Void)?  // (text, senderName, peerID)

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
}

// MARK: - MCSessionDelegate

extension MultipeerSession: MCSessionDelegate {

    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        updatePeer(peerID, state: state)
    }

    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
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
