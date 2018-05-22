/// Copyright (c) 2018 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import Photos
import Firebase
import MessageKit
import FirebaseFirestore

final class ChatViewController: MessagesViewController {
  
  private var isSendingPhoto = false {
    didSet {
      messageInputBar.leftStackViewItems.forEach { item in
        item.isEnabled = !isSendingPhoto
      }
    }
  }
  
  private var messages = [Message]()
  private var messageListener: ListenerRegistration?
  
  private let user: User
  private let channel: Channel
  
  deinit {
    messageListener?.remove()
  }
  
  init(user: User, channel: Channel) {
    self.user = user
    self.channel = channel
    super.init(nibName: nil, bundle: nil)
    
    title = channel.name
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    navigationItem.largeTitleDisplayMode = .never
    
    guard let ref = DatabaseHelper.chatReference(for: channel) else {
      navigationController?.popViewController(animated: true)
      return
    }
    
    messageListener = ref.addSnapshotListener { querySnapshot, error in
      guard let snapshot = querySnapshot else {
        print("Error listening for channel updates: \(error?.localizedDescription ?? "No error")")
        return
      }
      
      snapshot.documentChanges.forEach { change in
        self.handleDocumentChange(change)
      }
    }
    
    maintainPositionOnKeyboardFrameChanged = true
    messageInputBar.inputTextView.tintColor = .primary
    messageInputBar.sendButton.setTitleColor(.primary, for: .normal)
    
    let cameraItem = InputBarButtonItem(type: .system)
    cameraItem.tintColor = .primary
    cameraItem.image = #imageLiteral(resourceName: "camera")
    cameraItem.addTarget(
      self,
      action: #selector(cameraButtonPressed),
      for: .primaryActionTriggered
    )
    cameraItem.setSize(CGSize(width: 60, height: 30), animated: false)
    
    messageInputBar.leftStackView.alignment = .center
    messageInputBar.setLeftStackViewWidthConstant(to: 50, animated: false)
    messageInputBar.setStackViewItems([cameraItem], forStack: .left, animated: false)
    
    messageInputBar.delegate = self
    messagesCollectionView.messagesDataSource = self
    messagesCollectionView.messagesLayoutDelegate = self
    messagesCollectionView.messagesDisplayDelegate = self
  }
  
  // MARK: - Actions
  
  @objc private func cameraButtonPressed() {
    let picker = UIImagePickerController()
    picker.delegate = self
    
    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      picker.sourceType = .camera
    } else {
      picker.sourceType = .photoLibrary
    }
    
    present(picker, animated: true, completion: nil)
  }
  
  // MARK: - Helpers
  
  private func insertNewMessage(_ message: Message) {
    guard !messages.contains(message) else {
      return
    }
    
    messages.append(message)
    messages.sort()
    
    if let index = messages.index(of: message) {
      let shouldScrollToBottom = messagesCollectionView.isAtBottom && index == (messages.count - 1)
      
      messagesCollectionView.performBatchUpdates({
        self.messagesCollectionView.insertSections(IndexSet(integer: index))
      }) { _ in
        if shouldScrollToBottom {
          self.messagesCollectionView.scrollToBottom(animated: true)
        }
      }
    } else {
      messagesCollectionView.reloadDataAndKeepOffset()
    }
  }
  
  private func handleDocumentChange(_ change: DocumentChange) {
    guard var message = Message(document: change.document) else {
      return
    }
    
    switch change.type {
    case .added:
      if let url = message.downloadURL {
        StorageHelper.dowloadImage(at: url) { image in
          guard let image = image else {
            return
          }
          
          message.image = image
          self.insertNewMessage(message)
        }
      } else {
        insertNewMessage(message)
      }
      
    default:
      break
    }
  }
  
  private func sendPhoto(_ image: UIImage) {
    isSendingPhoto = true
    
    StorageHelper.uploadImage(image, to: channel) { url in
      self.isSendingPhoto = false
      
      guard let url = url else {
        return
      }
      
      var message = Message(user: self.user, image: image)
      message.downloadURL = url
      
      DatabaseHelper.saveMessage(to: self.channel, message: message)
      self.messagesCollectionView.scrollToBottom()
    }
  }
  
}

// MARK: - MessagesDisplayDelegate

extension ChatViewController: MessagesDisplayDelegate {
  
  func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
    return isFromCurrentSender(message: message) ? .primary : .incomingMessage
  }
  
  func shouldDisplayHeader(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> Bool {
    return false
  }
  
  func messageStyle(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
    let corner: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
    return .bubbleTail(corner, .curved)
  }
  
}

// MARK: - MessagesLayoutDelegate

extension ChatViewController: MessagesLayoutDelegate {

  func avatarSize(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGSize {
    return .zero
  }
  
  func footerViewSize(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGSize {
    return CGSize(width: 0, height: 8)
  }
  
  func heightForLocation(message: MessageType, at indexPath: IndexPath, with maxWidth: CGFloat, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
    return 0
  }
  
}

// MARK: - MessagesDataSource

extension ChatViewController: MessagesDataSource {
  
  func currentSender() -> Sender {
    return Sender(id: user.uid, displayName: AppSettings.displayName)
  }
  
  func numberOfMessages(in messagesCollectionView: MessagesCollectionView) -> Int {
    return messages.count
  }
  
  func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
    return messages[indexPath.section]
  }
  
  func cellTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
    let name = message.sender.displayName
    return NSAttributedString(
      string: name,
      attributes: [
        .font: UIFont.preferredFont(forTextStyle: .caption1),
        .foregroundColor: UIColor(white: 0.3, alpha: 1)
      ]
    )
  }
  
}

// MARK: - MessageInputBarDelegate

extension ChatViewController: MessageInputBarDelegate {
  
  func messageInputBar(_ inputBar: MessageInputBar, didPressSendButtonWith text: String) {
    let message = Message(user: user, content: text)
    
    DatabaseHelper.saveMessage(to: channel, message: message) { error in
      if let e = error {
        print("Error sending message: \(e.localizedDescription)")
        return
      }
      
      self.messagesCollectionView.scrollToBottom()
    }
    
    inputBar.inputTextView.text = ""
  }
  
}

// MARK: - UIImagePickerControllerDelegate

extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
    picker.dismiss(animated: true, completion: nil)
    
    if let asset = info[UIImagePickerControllerPHAsset] as? PHAsset {
      let size = CGSize(width: 500, height: 500)
      PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: nil) { result, info in
        guard let image = result else {
          return
        }
        
        self.sendPhoto(image)
      }
    } else if let image = info[UIImagePickerControllerOriginalImage] as? UIImage {
      sendPhoto(image)
    }
  }
  
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true, completion: nil)
  }
  
}
